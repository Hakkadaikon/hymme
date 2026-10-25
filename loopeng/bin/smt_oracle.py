#!/usr/bin/env python3
"""SMT oracle: check named claims over all inputs with Z3, and check the checks.

For pure decisions (predicates, rule/config sets, conversions) the question is
"does this hold for every input?", not "in what order?". A model file states
each claim as a Z3 formula; the oracle asks Z3 for an input that breaks it.

A model is a Python file defining `properties()` -> list of dicts:
    name     identifier shown in the report
    expect   "HOLDS"    : no input breaks the claim (a contract to lock)
             "VIOLATED" : some input breaks it (a known hole, or a satisfiability
                          check written as Not(cond): a witness proves cond can match)
    claim    z3 BoolRef
    broken   z3 BoolRef, required when expect is HOLDS: the same claim over a
             deliberately broken model (guard removed, negation dropped). It must
             come out VIOLATED, or the claim constrains nothing.

Usage:
    smt_oracle.py <model.py> [--timeout MS]
    smt_oracle.py --selfcheck

Exit: 0 every verdict matches, 1 a mismatch or a claim that is not load-bearing
(a broken variant Z3 cannot decide counts as not load-bearing: nothing showed the claim bites),
2 the model cannot be loaded, 3 Z3 answered unknown (re-state the claim in a
decidable fragment before trusting anything).
"""
import argparse
import importlib.util
import sys

import z3

VERDICTS = ("HOLDS", "VIOLATED")


class ModelError(Exception):
    pass


def classify(result):
    if result == z3.unsat:
        return "HOLDS"
    return "VIOLATED" if result == z3.sat else "UNKNOWN"


def decide(claim, timeout_ms):
    """(verdict, witness) where witness lists an input breaking the claim."""
    s = z3.Solver()
    s.set(timeout=timeout_ms)
    s.add(z3.Not(claim))
    verdict = classify(s.check())
    if verdict != "VIOLATED":
        return verdict, ""
    m = s.model()
    return verdict, ", ".join(sorted(f"{d.name()} = {m[d]}" for d in m.decls()))


def load(path):
    spec = importlib.util.spec_from_file_location("smt_model", path)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
        props = list(mod.properties())
    except Exception as e:  # the model is user code; report whatever it raised
        raise ModelError(f"{path}: {type(e).__name__}: {e}")
    if not props:
        raise ModelError(f"{path}: properties() returned nothing to check")
    for p in props:
        if not {"name", "expect", "claim"} <= set(p):
            raise ModelError(f"property {p!r} needs name, expect and claim")
        if p["expect"] not in VERDICTS:
            raise ModelError(f"{p['name']}: expect must be HOLDS or VIOLATED, not {p['expect']!r}")
        for key in ("claim", "broken"):
            # a Python bool would be decided as a constant, not over the inputs
            if key in p and not (isinstance(p[key], z3.ExprRef) and z3.is_bool(p[key])):
                raise ModelError(f"{p['name']}: {key} must be a z3 Bool expression, not {type(p[key]).__name__}")
    return props


def run(props, timeout_ms):
    """(exit code, report lines)."""
    lines, failed, unknown = [], False, False
    for p in props:
        verdict, witness = decide(p["claim"], timeout_ms)
        line = f"{p['name']}: {verdict}" + (f"  witness: {witness}" if witness else "")
        if verdict == "UNKNOWN":
            unknown = True
            lines.append(line + "  <- Z3 gave up; re-state the claim")
            continue
        if verdict != p["expect"]:
            failed = True
            lines.append(line + f"  <- expected {p['expect']}")
            continue
        if p["expect"] == "HOLDS":
            if "broken" not in p:
                failed = True
                line += "  <- no broken variant: add one to show the claim constrains something"
            else:
                bverdict, bwitness = decide(p["broken"], timeout_ms)
                if bverdict == "VIOLATED":
                    line += f"  (broken variant caught: {bwitness})"
                else:
                    failed = True
                    line += f"  <- not load-bearing: the broken variant is {bverdict} too"
        lines.append(line)
    return (1 if failed else 3 if unknown else 0), lines


def _selfcheck():
    """assert-based check of the verdict logic. Run: --selfcheck"""
    assert classify(z3.unknown) == "UNKNOWN"
    x = z3.Int("x")
    assert decide(x * x >= 0, 1000) == ("HOLDS", "")
    v, w = decide(x > 0, 1000)
    assert v == "VIOLATED" and w.startswith("x = "), (v, w)
    code, out = run([dict(name="P", expect="HOLDS", claim=x * x >= 0, broken=x >= 0)], 1000)
    assert code == 0, out
    code, out = run([dict(name="P", expect="HOLDS", claim=x * x >= 0, broken=x * x >= 0)], 1000)
    assert code == 1 and "not load-bearing" in out[0], out
    print("selfcheck OK")


def main():
    if sys.argv[1:] == ["--selfcheck"]:
        _selfcheck()
        return 0
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("model")
    ap.add_argument("--timeout", type=int, default=30000, help="per-claim Z3 timeout in ms")
    args = ap.parse_args()
    try:
        props = load(args.model)
    except ModelError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    code, lines = run(props, args.timeout)
    print("\n".join(lines))
    return code


if __name__ == "__main__":
    sys.exit(main())
