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

MESSAGES = {
    "description": "実システムのログ(JSONL)が TLA+ spec の許す振る舞いかを TLC で判定する",
    "help_help": "この使い方を表示して終わる",
    "help_spec": "判定に使う spec(.tla)",
    "help_log": "観測状態を1行に1つ並べたログ(.jsonl)",
    "help_cfg": "CONSTANT の値を持つ TLC の設定(既定: <spec>.cfg)",
    "help_timeout": "TLC を打ち切る秒数(既定: 600)",
    "help_all": "各ステップを独立に判定し、不一致を全件出す",
    "control_char": "文字列 {v!r} は TLA+ の文字列で表せない制御文字を含む",
    "bad_field": "レコードのフィールド {k!r} が TLA+ の識別子でない",
    "no_tla_form": "{v!r} に対応する TLA+ の値が無い(浮動小数と null は表せない)",
    "not_json": "{no} 行目: JSON でない({err})",
    "not_object": "{no} 行目: 変数を並べた JSON オブジェクトでない",
    "no_states": "ログに状態が無い",
    "unknown_vars": "{name} の変数でない: {unknown}(spec の変数: {variables})",
    "all_partial": (
        "--all は全行に全変数が要る({variables})。{no} 行目に欠けがある。--all を外せば見えない変数を spec に選ばせる"
    ),
    "no_tlc": "tlc が PATH に無い(hymme の skill-tools を入れる)",
    "timeout": "TLC が {timeout} 秒で終わらなかった。ログを短くするか、観測する変数を増やす",
    "tlc_failed": "生成した trace spec で TLC が失敗した:\n{tail}",
    "mismatch_init": "不一致: {no} 行目は {name} の初期状態ではない",
    "mismatch_step": "不一致: {no} 行目は {pno} 行目の後に {name} が許す遷移ではない",
    "state_line": "  {no} 行目: {obj}",
    "mismatch_count": "{states} 状態中 {count} 件の不一致",
    "ok": "適合: {log} の全 {states} 状態が {name} の振る舞い",
    "ok_all": "適合: {log} の全 {states} 状態が {name} の振る舞い(各ステップを独立に判定)",
    "no_variable": "{spec}: VARIABLE 宣言が無い",
    "error": "エラー: {e}",
    "selfcheck_ok": "自己検査 合格",
    "selfcheck_accepted": "自己検査 不合格: {v!r} を受け付けた",
}


def msg(code, **kw):
    """端末に出す文言をコードから引く(文言をこの表1か所に集める)。"""
    return MESSAGES[code].format(**kw)


class InputError(Exception):
    pass


def to_tla(v):
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        if re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", v):
            raise InputError(msg("control_char", v=v))
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
                raise InputError(msg("bad_field", k=k))
        return "[" + ", ".join(f"{k} |-> {to_tla(x)}" for k, x in v.items()) + "]"
    raise InputError(msg("no_tla_form", v=v))


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
            raise InputError(msg("not_json", no=no, err=e.msg)) from None
        if not isinstance(obj, dict):
            raise InputError(msg("not_object", no=no))
        steps.append((no, obj))
    if not steps:
        raise InputError(msg("no_states"))
    return steps


def observed_variables(spec_name, variables, steps):
    observed = sorted({k for _, obj in steps for k in obj})
    unknown = [k for k in observed if k not in variables]
    if unknown:
        raise InputError(
            msg("unknown_vars", name=spec_name, unknown=", ".join(unknown), variables=", ".join(variables))
        )
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
        raise InputError(msg("all_partial", variables=", ".join(variables), no=partial[0]))
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
    raise InputError(msg("no_tlc"))


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
            raise InputError(msg("timeout", timeout=timeout)) from None
        dump = work / "states.dump"
        return res.stdout + res.stderr, dump.read_text() if dump.exists() else ""


def tlc_failure(out):
    tail = "\n".join(out.strip().splitlines()[-25:])
    return InputError(msg("tlc_failed", tail=tail))


def state_line(no, obj):
    return msg("state_line", no=no, obj=json.dumps(obj, ensure_ascii=False))


def mismatch_init(name, steps):
    no, obj = steps[0]
    return msg("mismatch_init", no=no, name=name) + "\n" + state_line(no, obj)


def mismatch_step(name, steps, k):
    """Step from the k-th to the (k+1)-th state (1-based)."""
    (pno, pobj), (no, obj) = steps[k - 1], steps[k]
    return "\n".join([msg("mismatch_step", no=no, pno=pno, name=name), state_line(pno, pobj), state_line(no, obj)])


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
        return 1, "\n".join(lines) + "\n" + msg("mismatch_count", states=len(steps), count=len(lines))
    return 0, msg("ok_all", log=log, states=len(steps), name=name)


def check(spec, log, cfg=None, timeout=600, all_steps=False):
    """Return (exit code, message)."""
    spec = Path(spec)
    name = spec.stem
    text = spec.read_text()
    variables = spec_variables(text)
    if not variables:
        raise InputError(msg("no_variable", spec=spec))
    steps = read_trace(log)
    cfg = Path(cfg) if cfg else spec.with_suffix(".cfg")
    constants = cfg_constants(cfg.read_text()) if cfg.exists() else ""
    if all_steps:
        return check_all(spec, name, variables, steps, constants, log, timeout)
    module = trace_module(name, variables, steps)
    cfg_body = f"{constants}\nINIT {PREFIX}Init\nNEXT {PREFIX}Next\nINVARIANT {PREFIX}NotDone\nCHECK_DEADLOCK FALSE\n"
    out, dump = run_tlc(spec, name, module, cfg_body, [], timeout)
    if f"Invariant {PREFIX}NotDone is violated" in out:
        return 0, msg("ok", log=log, states=len(steps), name=name)
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
            raise AssertionError(msg("selfcheck_accepted", v=bad))
        except InputError:
            pass
    src = "VARIABLES a, \\* note\n  b,\n  c\n(* VARIABLE hidden *)\nVARIABLE d\nfoo == a"
    assert spec_variables(src) == ["a", "b", "c", "d"], spec_variables(src)
    cfg = "SPECIFICATION Spec\nCONSTANTS\n  N = 3\n  M = 2\nINVARIANT Inv\nCONSTANT K = 1\n"
    assert cfg_constants(cfg) == "CONSTANTS\n  N = 3\n  M = 2\nCONSTANT K = 1", cfg_constants(cfg)
    try:
        trace_module("S", ["x"], [(1, {"y": 1})])
        raise AssertionError(msg("selfcheck_accepted", v={"y": 1}))
    except InputError as e:
        assert "y" in str(e)
    print(msg("selfcheck_ok"))


def main():
    if sys.argv[1:] == ["--selfcheck"]:
        _selfcheck()
        return 0
    ap = argparse.ArgumentParser(description=msg("description"), add_help=False)
    ap.add_argument("-h", "--help", action="help", help=msg("help_help"))
    ap.add_argument("spec", help=msg("help_spec"))
    ap.add_argument("log", help=msg("help_log"))
    ap.add_argument("--cfg", help=msg("help_cfg"))
    ap.add_argument("--timeout", type=int, default=600, help=msg("help_timeout"))
    ap.add_argument("--all", action="store_true", help=msg("help_all"))
    args = ap.parse_args()
    try:
        code, out = check(args.spec, args.log, args.cfg, args.timeout, args.all)
    except (InputError, OSError) as e:
        print(msg("error", e=e), file=sys.stderr)
        return 2
    print(out)
    return code


if __name__ == "__main__":
    sys.exit(main())
