#!/usr/bin/env bash
# trace_check.py の回帰テスト: 実装のログ(JSONL)が spec の振る舞いとして許されるかの判定。
# 要: tlc, python3 が PATH にあること(flake の checks が用意する)。
set -euo pipefail

cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp" _JAVA_OPTIONS="-Djava.io.tmpdir=$tmp"
fail=0

ok() { echo "ok   $1"; }
ng() { echo "FAIL $1"; fail=1; }

cat >"$tmp/Cap.tla" <<'EOF'
---- MODULE Cap ----
EXTENDS Naturals, Sequences
CONSTANT Limit
VARIABLES count,
          served, log
vars == <<count, served, log>>
Init == count = 0 /\ served = 0 /\ log = <<>>
Serve(who) == count < Limit /\ count' = count + 1 /\ served' = served + 1
              /\ log' = Append(log, [who |-> who, ok |-> TRUE])
Next == \E w \in {"a", "b"} : Serve(w)
====
EOF
printf 'CONSTANT Limit = 3\nINIT Init\nNEXT Next\n' >"$tmp/Cap.cfg"

jsonl() { # jsonl <name> <line>...
  local n="$1"
  shift
  printf '%s\n' "$@" >"$tmp/$n.jsonl"
}
jsonl good '{"count":0,"served":0,"log":[]}' \
  '{"count":1,"served":1,"log":[{"who":"a","ok":true}]}' \
  '{"count":2,"served":2,"log":[{"who":"a","ok":true},{"who":"b","ok":true}]}'
# 3 行目: count が増えないまま served だけ進む(lost update)
jsonl lost '{"count":0,"served":0,"log":[]}' \
  '{"count":1,"served":1,"log":[{"who":"a","ok":true}]}' \
  '{"count":1,"served":2,"log":[{"who":"a","ok":true},{"who":"b","ok":true}]}'
# 観測できるのは count だけ(served と log は spec に選ばせる)
jsonl partial '{"count":0}' '{"count":1}' '{"count":2}' '{"count":3}'
# Limit=3 を超える: cfg の CONSTANT が効いていれば 5 行目で止まる
jsonl over '{"count":0}' '{"count":1}' '{"count":2}' '{"count":3}' '{"count":4}'
jsonl badinit '{"count":5,"served":0,"log":[]}' '{"count":6,"served":1,"log":[{"who":"a","ok":true}]}'
jsonl unknown '{"count":0,"nosuch":1}'
jsonl blank '{"count":0}' '' '{"count":1}'
jsonl notjson '{"count":0}' 'count=1'

run() { # run <want-exit> <jsonl> [want-substring]
  local got=0
  python3 loopeng/bin/trace_check.py "$tmp/Cap.tla" "$tmp/$2.jsonl" >"$tmp/out" 2>&1 || got=$?
  if [ "$got" -ne "$1" ]; then
    ng "$2: exit $got (want $1)"
    tail -20 "$tmp/out"
  elif [ -n "${3:-}" ] && ! grep -qF "$3" "$tmp/out"; then
    ng "$2: output lacks '$3'"
    tail -20 "$tmp/out"
  else
    ok "$2 -> $got${3:+ ($3)}"
  fi
}

run 0 good "OK"
run 1 lost "line 3"
run 0 partial "OK"
run 1 over "line 5"
run 1 badinit "line 1 is not an initial state"
run 2 unknown "nosuch"
run 0 blank "OK"
run 2 notjson "line 2"

# 隠れた変数の選び方で経路が分かれる: mode=1 の枝は 2 行目で行き止まるが、mode=2 の枝が最後まで届く
cat >"$tmp/Step.tla" <<'EOF'
---- MODULE Step ----
EXTENDS Naturals
VARIABLES x, mode
Init == x = 0 /\ mode \in {1, 2}
Next == x < 10 /\ x' = x + mode /\ UNCHANGED mode
====
EOF
printf '%s\n' '{"x":0}' '{"x":2}' '{"x":4}' >"$tmp/branch.jsonl"
printf '%s\n' '{"x":0}' '{"x":2}' '{"x":3}' >"$tmp/branchbad.jsonl"
for case in "0 branch OK" "1 branchbad line 3"; do
  set -- $case
  got=0
  python3 loopeng/bin/trace_check.py "$tmp/Step.tla" "$tmp/$2.jsonl" >"$tmp/out" 2>&1 || got=$?
  if [ "$got" -eq "$1" ] && grep -qF "${*:3}" "$tmp/out"; then ok "$2 -> $got"; else ng "$2: exit $got"; tail -20 "$tmp/out"; fi
done

# --all: 全変数を観測した行は、ステップごとに独立に判定してずれを全件出す
jsonl two '{"count":0,"served":0,"log":[]}' \
  '{"count":1,"served":2,"log":[{"who":"a","ok":true}]}' \
  '{"count":2,"served":3,"log":[{"who":"a","ok":true},{"who":"b","ok":true}]}' \
  '{"count":1,"served":3,"log":[{"who":"a","ok":true},{"who":"b","ok":true}]}'
got=0
python3 loopeng/bin/trace_check.py --all "$tmp/Cap.tla" "$tmp/two.jsonl" >"$tmp/out" 2>&1 || got=$?
if [ "$got" -eq 1 ] && grep -qF "line 2" "$tmp/out" && grep -qF "line 4" "$tmp/out" && ! grep -qF "line 3 " "$tmp/out"; then
  ok "--all two -> 1 (line 2, line 4)"
else
  ng "--all two: exit $got"
  cat "$tmp/out"
fi
run_all() { # run_all <want-exit> <jsonl> <want-substring>
  local got=0
  python3 loopeng/bin/trace_check.py --all "$tmp/Cap.tla" "$tmp/$2.jsonl" >"$tmp/out" 2>&1 || got=$?
  if [ "$got" -eq "$1" ] && grep -qF -- "$3" "$tmp/out"; then ok "--all $2 -> $got ($3)"; else ng "--all $2: exit $got"; cat "$tmp/out"; fi
}
run_all 0 good "OK"
run_all 1 badinit "line 1 is not an initial state"
# 一部の変数しか無い行は独立判定できないので断る(既定のモードを使えと案内する)
run_all 2 partial "every variable"

# 同じ状態が続く行は spec の振る舞い(stutter)として許す
jsonl stutter '{"count":0}' '{"count":0}' '{"count":1}' '{"count":1}'
run 0 stutter "OK"
jsonl stutterall '{"count":0,"served":0,"log":[]}' '{"count":0,"served":0,"log":[]}'
run_all 0 stutterall "OK"
# 1 行だけのログ: 初期状態なら適合、そうでなければ不一致
jsonl one '{"count":0,"served":0,"log":[]}'
jsonl onebad '{"count":2}'
run 0 one "OK"
run 1 onebad "line 1 is not an initial state"
# 入力の誤りは exit 2
printf '' >"$tmp/empty.jsonl"
run 2 empty "no states"
jsonl notobj '[1]'
run 2 notobj "JSON object"
run_all 2 unknown "nosuch"
printf '%s\n' '---- MODULE NoVar ----' 'Init == TRUE' 'Next == TRUE' '====' >"$tmp/NoVar.tla"
got=0
python3 loopeng/bin/trace_check.py "$tmp/NoVar.tla" "$tmp/good.jsonl" >"$tmp/out" 2>&1 || got=$?
[ "$got" -eq 2 ] && grep -qF "no VARIABLE" "$tmp/out" && ok "spec without VARIABLE -> 2" || { ng "NoVar: exit $got"; cat "$tmp/out"; }
# TLC 自体が失敗したら判定と取り違えず exit 2(CONSTANT が無い cfg、構文エラーの spec)
printf 'INIT Init\nNEXT Next\n' >"$tmp/noconst.cfg"
for mode in "" "--all"; do
  got=0
  python3 loopeng/bin/trace_check.py $mode --cfg "$tmp/noconst.cfg" "$tmp/Cap.tla" "$tmp/good.jsonl" >"$tmp/out" 2>&1 || got=$?
  [ "$got" -eq 2 ] && grep -qF "TLC failed" "$tmp/out" && ok "TLC failure ${mode:-default} -> 2" || { ng "TLC failure ${mode:-default}: exit $got"; cat "$tmp/out"; }
done
printf '%s\n' '---- MODULE Broken ----' 'VARIABLE x' 'Init == x = = 0' "Next == x' = x" '====' >"$tmp/Broken.tla"
got=0
python3 loopeng/bin/trace_check.py "$tmp/Broken.tla" "$tmp/partial.jsonl" >"$tmp/out" 2>&1 || got=$?
[ "$got" -eq 2 ] && ok "syntax error spec -> 2" || { ng "Broken: exit $got"; cat "$tmp/out"; }
# 非 ASCII の文字列は通す。spec が Integers を読まなくても、ログの負の数は TLC のエラーでなく不一致になる
cat >"$tmp/Str.tla" <<'EOF2'
---- MODULE Str ----
VARIABLES s, n
Init == s = "あ" /\ n = 0
Next == s' = "い" /\ UNCHANGED n
====
EOF2
printf '%s\n' '{"s":"あ","n":0}' '{"s":"い","n":0}' >"$tmp/str.jsonl"
printf '%s\n' '{"s":"あ","n":0}' '{"s":"い","n":-1}' >"$tmp/neg.jsonl"
for mode in "" "--all"; do
  for c in "0 str OK" "1 neg line 2 is not a step"; do
    set -- $c
    got=0
    python3 loopeng/bin/trace_check.py $mode "$tmp/Str.tla" "$tmp/$2.jsonl" >"$tmp/out" 2>&1 || got=$?
    if [ "$got" -eq "$1" ] && grep -qF "${*:3}" "$tmp/out"; then ok "$2 ${mode:-default} -> $got"; else ng "$2 ${mode:-default}: exit $got"; cat "$tmp/out"; fi
  done
done
# --all: 長い値で TLC が状態を折り返しても、ずれを TLC のエラーと取り違えない
long="$(python3 -c 'import json; print(json.dumps([{"who":"a","ok":True}]*40))')"
printf '{"count":0,"served":0,"log":[]}\n{"count":0,"served":0,"log":%s}\n' "$long" >"$tmp/longv.jsonl"
run_all 1 longv "line 2 is not a step"

# 生成した trace spec は spec の隣に残さない(tasks/loopeng を汚さない)
if ls "$tmp" | grep -q '_Trace'; then ng "left a _Trace module next to the spec"; else ok "no _Trace module left behind"; fi

python3 loopeng/bin/trace_check.py --selfcheck >/dev/null && ok "--selfcheck" || ng "--selfcheck"

exit "$fail"
