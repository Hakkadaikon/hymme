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

MESSAGES = {
    "description": "SMT オラクル: 名前付きの性質が全入力で成り立つかを Z3 で検査し、検査が効いているかも確かめる",
    "help_model": "properties() を定義したモデルファイル(.py)",
    "help_timeout": "性質1件あたりの Z3 のタイムアウト(ミリ秒)",
    "load_failed": "{path}: {kind}: {err}",
    "no_props": "{path}: properties() が検査する性質を1件も返さない",
    "missing_keys": "性質 {p} には name・expect・claim が要る",
    "bad_expect": "{name}: expect は HOLDS か VIOLATED にする({got} は不可)",
    "not_bool": "{name}: {key} は z3 の Bool 式にする({got} は不可)",
    "verdict": "{name}: {verdict}",
    "witness": "  witness(破る入力): {w}",
    "gave_up": "  <- Z3 が判定を諦めた。性質を書き直す",
    "mismatch": "  <- 期待は {expect}",
    "no_broken": "  <- 壊した版が無い。性質が何かを縛っていると示すために足す",
    "broken_caught": "  (壊した版は捕まった: {w})",
    "not_load_bearing": "  <- 効いていない: 壊した版も {verdict}",
    "error": "エラー: {err}",
    "selfcheck_ok": "自己検査 合格",
}


def msg(code, **kw):
    """端末に出す文言をコードから引く(文言をこの表1か所に集める)。"""
    return MESSAGES.get(code, "未知のメッセージコード: " + code).format(**kw)


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
        raise ModelError(msg("load_failed", path=path, kind=type(e).__name__, err=e)) from e
    if not props:
        raise ModelError(msg("no_props", path=path))
    for p in props:
        if not {"name", "expect", "claim"} <= set(p):
            raise ModelError(msg("missing_keys", p=repr(p)))
        if p["expect"] not in VERDICTS:
            raise ModelError(msg("bad_expect", name=p["name"], got=repr(p["expect"])))
        for key in ("claim", "broken"):
            # a Python bool would be decided as a constant, not over the inputs
            if key in p and not (isinstance(p[key], z3.ExprRef) and z3.is_bool(p[key])):
                raise ModelError(msg("not_bool", name=p["name"], key=key, got=type(p[key]).__name__))
    return props


def run(props, timeout_ms):
    """(exit code, report lines)."""
    lines, failed, unknown = [], False, False
    for p in props:
        verdict, witness = decide(p["claim"], timeout_ms)
        line = msg("verdict", name=p["name"], verdict=verdict) + (msg("witness", w=witness) if witness else "")
        if verdict == "UNKNOWN":
            unknown = True
            lines.append(line + msg("gave_up"))
            continue
        if verdict != p["expect"]:
            failed = True
            lines.append(line + msg("mismatch", expect=p["expect"]))
            continue
        if p["expect"] == "HOLDS":
            if "broken" not in p:
                failed = True
                line += msg("no_broken")
            else:
                bverdict, bwitness = decide(p["broken"], timeout_ms)
                if bverdict == "VIOLATED":
                    line += msg("broken_caught", w=bwitness)
                else:
                    failed = True
                    line += msg("not_load_bearing", verdict=bverdict)
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
    assert code == 1 and msg("not_load_bearing", verdict="HOLDS") in out[0], out
    print(msg("selfcheck_ok"))


def main():
    if sys.argv[1:] == ["--selfcheck"]:
        _selfcheck()
        return 0
    ap = argparse.ArgumentParser(description=msg("description"))
    ap.add_argument("model", help=msg("help_model"))
    ap.add_argument("--timeout", type=int, default=30000, help=msg("help_timeout"))
    args = ap.parse_args()
    try:
        props = load(args.model)
    except ModelError as e:
        print(msg("error", err=e), file=sys.stderr)
        return 2
    code, lines = run(props, args.timeout)
    print("\n".join(lines))
    return code


if __name__ == "__main__":
    sys.exit(main())
