#!/usr/bin/env bash
# smt_oracle.py の回帰テスト: 性質の判定・期待との照合・壊した版での load-bearing 確認。
# 要: z3 を import できる python3 が PATH にあること(flake の checks が用意する)。
set -euo pipefail

cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

ok() { echo "ok   $1"; }
ng() {
  echo "FAIL $1"
  fail=1
}

model() { # model <name> <python body of properties()>
  printf 'from z3 import *\n\ndef properties():\n    x = Int("x")\n%s\n' "$2" >"$tmp/$1.py"
}
# 0..100 に丸める関数は常に範囲内(HOLDS)。丸めを外した壊した版は範囲を外れる(VIOLATED)
model good '    clamp = If(x < 0, 0, If(x > 100, 100, x))
    return [dict(name="ClampInRange", expect="HOLDS",
                 claim=And(0 <= clamp, clamp <= 100), broken=And(0 <= x, x <= 100))]'
# 期待は HOLDS だが実際は破れる: x=-1 のような反例が出る
model wrong '    return [dict(name="NonNegative", expect="HOLDS", claim=x >= 0, broken=x >= 1)]'
# 壊した版でも成り立つ = この検査は何も縛っていない
model unguarded '    return [dict(name="Tautology", expect="HOLDS", claim=Or(x > 0, x <= 0), broken=Or(x >= 0, x < 0))]'
model nobroken '    return [dict(name="Tautology", expect="HOLDS", claim=Or(x > 0, x <= 0))]'
# 設定が死んでいないこと: Not(条件) が VIOLATED = 条件を満たす入力がある(witness が出る)
model alive '    return [dict(name="RuleCanMatch", expect="VIOLATED", claim=Not(And(x > 18, x < 20)))]'
model dead '    return [dict(name="RuleCanMatch", expect="VIOLATED", claim=Not(And(x > 20, x < 18)))]'
model badexpect '    return [dict(name="P", expect="MAYBE", claim=x >= 0, broken=x > 0)]'
printf 'raise RuntimeError("model blew up")\n' >"$tmp/crash.py"
# 合格と不一致が並ぶ: 1件でも外れれば exit 1、両方の行が出る
model mixed '    return [dict(name="Ok", expect="HOLDS", claim=x * x >= 0, broken=x >= 0),
            dict(name="Bad", expect="HOLDS", claim=x >= 0, broken=x >= 1)]'
model nokey '    return [dict(name="P", claim=x >= 0)]'
model empty '    return []'
# Python の bool は入力に依らない定数として判定されてしまう
model pybool '    return [dict(name="P", expect="HOLDS", claim=x is not None, broken=x >= 0)]'
# 非線形で Z3 が決めきれない(n=3 のフェルマー)。短く打ち切って unknown にする
fermat='y = Int("y"); z = Int("z")
    hard = Not(And(x > 0, y > 0, z > 0, x * x * x + y * y * y == z * z * z))'
model unknown "    $fermat
    return [dict(name=\"Fermat3\", expect=\"HOLDS\", claim=hard, broken=x >= 1)]"
model unknownmixed "    $fermat
    return [dict(name=\"Fermat3\", expect=\"HOLDS\", claim=hard, broken=x >= 1),
            dict(name=\"Bad\", expect=\"HOLDS\", claim=x >= 0, broken=x >= 1)]"
model brokenunknown "    $fermat
    return [dict(name=\"P\", expect=\"HOLDS\", claim=x * x >= 0, broken=hard)]"

run() { # run <want-exit> <model> [want-substring]
  local got=0
  python3 loopeng/bin/smt_oracle.py "$tmp/$2.py" >"$tmp/out" 2>&1 || got=$?
  if [ "$got" -ne "$1" ]; then
    ng "$2: exit $got (want $1)"
    cat "$tmp/out"
  elif [ -n "${3:-}" ] && ! grep -qF -- "$3" "$tmp/out"; then
    ng "$2: output lacks '$3'"
    cat "$tmp/out"
  else
    ok "$2 -> $got${3:+ ($3)}"
  fi
}

run 0 good "ClampInRange: HOLDS"
run 1 wrong "x = -"
run 1 unguarded "not load-bearing"
run 1 nobroken "no broken variant"
run 0 alive "x = 19"
run 1 dead "HOLDS"
run 2 badexpect "MAYBE"
run 2 crash "model blew up"
run 1 mixed "Ok: HOLDS"
run 1 mixed "Bad: VIOLATED"
run 2 nokey "needs name, expect and claim"
run 2 empty "nothing to check"
run 2 pybool "z3 Bool expression"
run_t() { # run_t <want-exit> <model> <want-substring>  (Z3 を 200ms で打ち切る: 線形の性質は解け、非線形は決めきれない)
  local got=0
  python3 loopeng/bin/smt_oracle.py --timeout 200 "$tmp/$2.py" >"$tmp/out" 2>&1 || got=$?
  if [ "$got" -eq "$1" ] && grep -qF -- "$3" "$tmp/out"; then ok "$2 -> $got ($3)"; else
    ng "$2: exit $got (want $1)"
    cat "$tmp/out"
  fi
}
run_t 3 unknown "UNKNOWN"
run_t 1 unknownmixed "Bad: VIOLATED"
run_t 1 brokenunknown "not load-bearing"

python3 loopeng/bin/smt_oracle.py --selfcheck >/dev/null && ok "--selfcheck" || ng "--selfcheck"

exit "$fail"
