#!/usr/bin/env python3
"""Trace check: is a log of the real system a behavior the TLA+ spec allows?

A model-checked spec says nothing about the code until something ties the two
together. This replays an observed run against the spec: each line of a JSONL
log is one observed state (`{"var": value, ...}`), and TLC is asked whether
some behavior of the spec passes through those states in that order.

Lines may name only the variables the system can observe; the spec chooses the
hidden ones. A run conforms when TLC reaches the last line. Otherwise the first
line no allowed behavior reaches is reported: that step is where the code did
something the spec forbids (or the spec forgot something the code must do).

With --all every line must name every variable; each step is then judged on
its own (does some Next step lead from line k to line k+1?) and every mismatch
is reported, not just the first. Line 1 is also checked against Init.

Usage:
    trace_check.py [--all] <Spec.tla> <run.jsonl> [--cfg Spec.cfg] [--timeout SEC]
    trace_check.py --selfcheck

Exit: 0 conforms, 1 mismatch (line reported), 2 bad input or TLC error.

JSON -> TLA+: numbers, strings, booleans, lists as sequences, objects as records,
{"$set": [...]} as a set.
shortcut: no model values or functions with non-string domains; write the log
in records/sequences, or extend to_tla() when a spec needs them.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PREFIX = "TC_"  # generated names; a spec using this prefix would collide
CFG_KEYWORDS = {
    "CONSTANT",
    "CONSTANTS",
    "INIT",
    "NEXT",
    "SPECIFICATION",
    "INVARIANT",
    "INVARIANTS",
    "PROPERTY",
    "PROPERTIES",
    "SYMMETRY",
    "VIEW",
    "CONSTRAINT",
    "CONSTRAINTS",
    "ACTION_CONSTRAINT",
    "ACTION_CONSTRAINTS",
    "CHECK_DEADLOCK",
    "POSTCONDITION",
    "ALIAS",
}


class InputError(Exception):
    pass


def to_tla(v):
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        if re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", v):
            raise InputError(f"string {v!r} has a control character TLA+ strings cannot escape")
        return json.dumps(v, ensure_ascii=False)  # \" \\ \n \t \r mean the same in TLA+
    if isinstance(v, list):
        return "<<" + ", ".join(to_tla(x) for x in v) + ">>"
    if isinstance(v, dict):
        if set(v) == {"$set"} and isinstance(v["$set"], list):
            return "{" + ", ".join(to_tla(x) for x in v["$set"]) + "}"
        if not v:
            return "[x \\in {} |-> 0]"
        for k in v:
            if not re.fullmatch(r"[A-Za-z_]\w*", k):
                raise InputError(f"record field {k!r} is not a TLA+ identifier")
        return "[" + ", ".join(f"{k} |-> {to_tla(x)}" for k, x in v.items()) + "]"
    raise InputError(f"no TLA+ form for {v!r} (floats and null have none)")


def strip_comments(text):
    text = re.sub(r"\(\*.*?\*\)", " ", text, flags=re.S)
    return re.sub(r"\\\*[^\n]*", " ", text)


def spec_variables(text):
    """Names declared by every VARIABLE/VARIABLES in the module, in order."""
    names = []
    for m in re.finditer(r"\bVARIABLES?\b((?:\s*[A-Za-z_]\w*\s*,)*\s*[A-Za-z_]\w*)", strip_comments(text)):
        names += [n.strip() for n in m.group(1).split(",")]
    return names


def cfg_constants(text):
    """The CONSTANT/CONSTANTS sections of a TLC config, verbatim."""
    keep, out = False, []
    for line in strip_comments(text).splitlines():
        head = line.split()[0] if line.split() else ""
        if head in CFG_KEYWORDS:
            keep = head.startswith("CONSTANT")
        if keep:
            out.append(line)
    return "\n".join(out)


def read_trace(path):
    """[(file line number, {var: value})], skipping blank lines."""
    steps = []
    for no, line in enumerate(Path(path).read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as e:
            raise InputError(f"line {no}: not JSON ({e.msg})")
        if not isinstance(obj, dict):
            raise InputError(f"line {no}: expected a JSON object of variables")
        steps.append((no, obj))
    if not steps:
        raise InputError("the log has no states")
    return steps


def observed_variables(spec_name, variables, steps):
    observed = sorted({k for _, obj in steps for k in obj})
    unknown = [k for k in observed if k not in variables]
    if unknown:
        raise InputError(f"not variables of {spec_name}: {', '.join(unknown)} (spec has {', '.join(variables)})")
    return observed


def module_head(spec_name, counter, steps):
    trace = ",\n    ".join(to_tla(obj) for _, obj in steps)
    return f"""---- MODULE {spec_name}_Trace ----
EXTENDS {spec_name}, Integers, Sequences, TLC
VARIABLE {PREFIX}{counter}
{PREFIX}Trace == <<
    {trace}
  >>"""


def step_or_stutter(variables):
    """A behavior of Init /\\ [][Next]_vars may repeat a state, so a log line that changed nothing is allowed."""
    return f"(Next \\/ UNCHANGED <<{', '.join(variables)}>>)"


def trace_module(spec_name, variables, steps):
    observed = observed_variables(spec_name, variables, steps)

    def obs(at, prime):
        return (
            "\n".join(
                f'    /\\ ("{v}" \\in DOMAIN {PREFIX}Trace[{at}] => {v}{prime} = {PREFIX}Trace[{at}].{v})'
                for v in observed
            )
            or "    /\\ TRUE"
        )

    return f"""{module_head(spec_name, "i", steps)}
{PREFIX}Init ==
    /\\ {PREFIX}i = 1
    /\\ Init
{obs(1, "")}
{PREFIX}Next ==
    /\\ {PREFIX}i < Len({PREFIX}Trace)
    /\\ {PREFIX}i' = {PREFIX}i + 1
    /\\ {step_or_stutter(variables)}
{obs(f"{PREFIX}i + 1", "'")}
{PREFIX}NotDone == {PREFIX}i < Len({PREFIX}Trace)
====
"""


def step_module(spec_name, variables, steps):
    """--all: one initial state per checked line k (all variables bound), judged on its own."""
    observed_variables(spec_name, variables, steps)
    partial = [no for no, obj in steps if set(obj) != set(variables)]
    if partial:
        raise InputError(
            f"--all needs every variable on every line ({', '.join(variables)}); "
            f"line {partial[0]} lacks some. Drop --all to let the spec choose hidden variables"
        )
    bind = "\n".join(f"    /\\ {v} = {PREFIX}Trace[{PREFIX}k].{v}" for v in variables)
    nxt = " /\\ ".join(f"{v}' = {PREFIX}Trace[{PREFIX}k + 1].{v}" for v in variables)
    return f"""{module_head(spec_name, "k", steps)}
{PREFIX}Init ==
    /\\ {PREFIX}k \\in 1..Len({PREFIX}Trace)
{bind}
{PREFIX}Stay == UNCHANGED <<{PREFIX}k, {", ".join(variables)}>>
{PREFIX}InitOK == {PREFIX}k = 1 => Init
{PREFIX}StepOK == {PREFIX}k < Len({PREFIX}Trace) => ENABLED ({step_or_stutter(variables)} /\\ {nxt})
====
"""


def tlc_command():
    if shutil.which("tlc"):
        return ["tlc"]
    raise InputError("tlc is not on PATH (install the hymme skill-tools)")


def run_tlc(spec, name, module, cfg_body, extra, timeout):
    """Run TLC on the generated module next to copies of the spec's modules; (output, dump text)."""
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for other in spec.parent.glob("*.tla"):  # modules the spec EXTENDS
            shutil.copy(other, work / other.name)
        (work / f"{name}_Trace.tla").write_text(module)
        (work / f"{name}_Trace.cfg").write_text(cfg_body)
        cmd = tlc_command() + [
            "-workers",
            "1",
            "-metadir",
            str(work / "meta"),
            "-dump",
            str(work / "states"),
            *extra,
            "-config",
            f"{name}_Trace.cfg",
            f"{name}_Trace.tla",
        ]
        try:
            res = subprocess.run(cmd, cwd=work, capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise InputError(f"TLC did not finish in {timeout}s; shorten the log or observe more variables")
        dump = work / "states.dump"
        return res.stdout + res.stderr, dump.read_text() if dump.exists() else ""


def tlc_failure(out):
    tail = "\n".join(out.strip().splitlines()[-25:])
    return InputError(f"TLC failed on the generated trace spec:\n{tail}")


def mismatch_init(name, steps):
    no, obj = steps[0]
    return f"MISMATCH: line {no} is not an initial state of {name}\n  line {no}: {json.dumps(obj, ensure_ascii=False)}"


def mismatch_step(name, steps, k):
    """Step from the k-th to the (k+1)-th state (1-based)."""
    (pno, pobj), (no, obj) = steps[k - 1], steps[k]
    return (
        f"MISMATCH: line {no} is not a step {name} allows after line {pno}\n"
        f"  line {pno}: {json.dumps(pobj, ensure_ascii=False)}\n  line {no}: {json.dumps(obj, ensure_ascii=False)}"
    )


def check_all(spec, name, variables, steps, constants, log, timeout):
    """--all: (exit code, message) listing every step no Next step explains."""
    module = step_module(name, variables, steps)
    cfg_body = (
        f"{constants}\nINIT {PREFIX}Init\nNEXT {PREFIX}Stay\n"
        f"INVARIANT {PREFIX}InitOK\nINVARIANT {PREFIX}StepOK\nCHECK_DEADLOCK FALSE\n"
    )
    out, _ = run_tlc(spec, name, module, cfg_body, ["-continue"], timeout)
    if "Model checking completed" not in out:
        raise tlc_failure(out)
    bad_init, bad_steps = False, set()
    # each violation prints "Error: Invariant <name> is violated by the initial state:" then the state,
    # one conjunct per line (long values wrap), ending at a blank line
    for inv, state in re.findall(r"Invariant (\w+) is violated[^\n]*\n(.*?)(?:\n\s*\n|\Z)", out, re.S):
        k = re.search(rf"{PREFIX}k = (\d+)", state)
        if not k:
            raise tlc_failure(out)
        if inv == f"{PREFIX}InitOK":
            bad_init = True
        else:
            bad_steps.add(int(k.group(1)))
    lines = ([mismatch_init(name, steps)] if bad_init else []) + [
        mismatch_step(name, steps, k) for k in sorted(bad_steps)
    ]
    if lines:
        return 1, "\n".join(lines) + f"\n{len(lines)} mismatch(es) in {len(steps)} states"
    return 0, f"OK: all {len(steps)} states of {log} are a behavior of {name} (each step checked on its own)"


def check(spec, log, cfg=None, timeout=600, all_steps=False):
    """Return (exit code, message)."""
    spec = Path(spec)
    name = spec.stem
    text = spec.read_text()
    variables = spec_variables(text)
    if not variables:
        raise InputError(f"{spec}: no VARIABLE declaration")
    steps = read_trace(log)
    cfg = Path(cfg) if cfg else spec.with_suffix(".cfg")
    constants = cfg_constants(cfg.read_text()) if cfg.exists() else ""
    if all_steps:
        return check_all(spec, name, variables, steps, constants, log, timeout)
    module = trace_module(name, variables, steps)
    cfg_body = f"{constants}\nINIT {PREFIX}Init\nNEXT {PREFIX}Next\nINVARIANT {PREFIX}NotDone\nCHECK_DEADLOCK FALSE\n"
    out, dump = run_tlc(spec, name, module, cfg_body, [], timeout)
    if f"Invariant {PREFIX}NotDone is violated" in out:
        return 0, f"OK: all {len(steps)} states of {log} are a behavior of {name}"
    if "No error has been found" not in out:
        raise tlc_failure(out)
    reached = [int(n) for n in re.findall(rf"{PREFIX}i = (\d+)", dump)]
    if not reached:
        return 1, mismatch_init(name, steps)
    return 1, mismatch_step(name, steps, max(reached))  # max: the last state some behavior reaches


def _selfcheck():
    """assert-based check of the parts that do not need TLC. Run: --selfcheck"""
    assert to_tla({"a": [1, True], "s": {"$set": ["x"]}}) == '[a |-> <<1, TRUE>>, s |-> {"x"}]'
    assert to_tla({}) == "[x \\in {} |-> 0]"
    assert to_tla('say "hi"') == '"say \\"hi\\""'
    for bad in (1.5, None, {"not-ident": 1}):
        try:
            to_tla(bad)
            raise AssertionError(f"accepted {bad!r}")
        except InputError:
            pass
    src = "VARIABLES a, \\* note\n  b,\n  c\n(* VARIABLE hidden *)\nVARIABLE d\nfoo == a"
    assert spec_variables(src) == ["a", "b", "c", "d"], spec_variables(src)
    cfg = "SPECIFICATION Spec\nCONSTANTS\n  N = 3\n  M = 2\nINVARIANT Inv\nCONSTANT K = 1\n"
    assert cfg_constants(cfg) == "CONSTANTS\n  N = 3\n  M = 2\nCONSTANT K = 1", cfg_constants(cfg)
    try:
        trace_module("S", ["x"], [(1, {"y": 1})])
        raise AssertionError("accepted an unknown variable")
    except InputError as e:
        assert "y" in str(e)
    print("selfcheck OK")


def main():
    if sys.argv[1:] == ["--selfcheck"]:
        _selfcheck()
        return 0
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("spec")
    ap.add_argument("log")
    ap.add_argument("--cfg", help="TLC config holding the CONSTANT values (default: <spec>.cfg)")
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--all", action="store_true", help="judge each step on its own and report every mismatch")
    args = ap.parse_args()
    try:
        code, msg = check(args.spec, args.log, args.cfg, args.timeout, args.all)
    except (InputError, OSError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    print(msg)
    return code


if __name__ == "__main__":
    sys.exit(main())
