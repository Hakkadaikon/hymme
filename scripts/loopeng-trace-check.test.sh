#!/usr/bin/env bash
# trace_check.py の回帰テスト: 実装のログ(JSONL)が spec の振る舞いとして許されるかの判定。
# 要: tlc, python3 が PATH にあること(flake の checks が用意する)。
set -euo pipefail

cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp" _JAVA_OPTIONS="-Djava.io.tmpdir=$tmp"
fail=0

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    ok) printf '合格   %s\n' "$2" ;;
    ng) printf '不合格 %s\n' "$2" ;;
    want_exit) printf '%s: exit %s(期待 %s)\n' "$2" "$3" "$4" ;;
    lacks) printf "%s: 出力に '%s' が無い\n" "$2" "$3" ;;
    has) printf "%s: 出力に '%s' がある\n" "$2" "$3" ;;
    left) printf '生成した _Trace モジュールが spec の隣に残った\n' ;;
    not_left) printf '_Trace モジュールは spec の隣に残っていない\n' ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}
ok() { msg ok "$1"; }
ng() {
  msg ng "$1"
  fail=1
}

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

check() { # check <label> <want-exit> <want-substring> <trace_check.py の引数...>
  local label="$1" want="$2" sub="$3" got=0
  shift 3
  python3 loopeng/bin/trace_check.py "$@" >"$tmp/out" 2>&1 || got=$?
  if [ "$got" -ne "$want" ]; then
    ng "$(msg want_exit "$label" "$got" "$want")"
    tail -20 "$tmp/out"
  elif [ -n "$sub" ] && ! grep -qF -- "$sub" "$tmp/out"; then
    ng "$(msg lacks "$label" "$sub")"
    tail -20 "$tmp/out"
  else
    ok "$label -> $got${sub:+ ($sub)}"
  fi
}
run() { check "$2" "$1" "${3:-}" "$tmp/Cap.tla" "$tmp/$2.jsonl"; }             # run <want-exit> <jsonl> [want-substring]
run_all() { check "--all $2" "$1" "$3" --all "$tmp/Cap.tla" "$tmp/$2.jsonl"; } # run_all <want-exit> <jsonl> <want-substring>

run 0 good "適合"
run 1 lost "3 行目は"
run 0 partial "適合"
run 1 over "5 行目は"
run 1 badinit "1 行目は Cap の初期状態ではない"
run 2 unknown "nosuch"
run 0 blank "適合"
run 2 notjson "2 行目: JSON でない"

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
check branch 0 "適合" "$tmp/Step.tla" "$tmp/branch.jsonl"
check branchbad 1 "3 行目は" "$tmp/Step.tla" "$tmp/branchbad.jsonl"

# --all: 全変数を観測した行は、ステップごとに独立に判定してずれを全件出す
jsonl two '{"count":0,"served":0,"log":[]}' \
  '{"count":1,"served":2,"log":[{"who":"a","ok":true}]}' \
  '{"count":2,"served":3,"log":[{"who":"a","ok":true},{"who":"b","ok":true}]}' \
  '{"count":1,"served":3,"log":[{"who":"a","ok":true},{"who":"b","ok":true}]}'
run_all 1 two "2 行目は"
run_all 1 two "4 行目は"
if grep -qF "3 行目は" "$tmp/out"; then ng "$(msg has "--all two" "3 行目は")"; fi
run_all 0 good "適合"
run_all 1 badinit "1 行目は Cap の初期状態ではない"
# 一部の変数しか無い行は独立判定できないので断る(既定のモードを使えと案内する)
run_all 2 partial "全行に全変数が要る"

# 同じ状態が続く行は spec の振る舞い(stutter)として許す
jsonl stutter '{"count":0}' '{"count":0}' '{"count":1}' '{"count":1}'
run 0 stutter "適合"
jsonl stutterall '{"count":0,"served":0,"log":[]}' '{"count":0,"served":0,"log":[]}'
run_all 0 stutterall "適合"
# 1 行だけのログ: 初期状態なら適合、そうでなければ不一致
jsonl one '{"count":0,"served":0,"log":[]}'
jsonl onebad '{"count":2}'
run 0 one "適合"
run 1 onebad "1 行目は Cap の初期状態ではない"
# 入力の誤りは exit 2
printf '' >"$tmp/empty.jsonl"
run 2 empty "ログに状態が無い"
jsonl notobj '[1]'
run 2 notobj "JSON オブジェクトでない"
run_all 2 unknown "nosuch"
printf '%s\n' '---- MODULE NoVar ----' 'Init == TRUE' 'Next == TRUE' '====' >"$tmp/NoVar.tla"
check "spec without VARIABLE" 2 "VARIABLE 宣言が無い" "$tmp/NoVar.tla" "$tmp/good.jsonl"
# TLC 自体が失敗したら判定と取り違えず exit 2(CONSTANT が無い cfg、構文エラーの spec)
printf 'INIT Init\nNEXT Next\n' >"$tmp/noconst.cfg"
check "TLC failure default" 2 "TLC が失敗した" --cfg "$tmp/noconst.cfg" "$tmp/Cap.tla" "$tmp/good.jsonl"
check "TLC failure --all" 2 "TLC が失敗した" --all --cfg "$tmp/noconst.cfg" "$tmp/Cap.tla" "$tmp/good.jsonl"
printf '%s\n' '---- MODULE Broken ----' 'VARIABLE x' 'Init == x = = 0' "Next == x' = x" '====' >"$tmp/Broken.tla"
check "syntax error spec" 2 "" "$tmp/Broken.tla" "$tmp/partial.jsonl"
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
check "str default" 0 "適合" "$tmp/Str.tla" "$tmp/str.jsonl"
check "neg default" 1 "2 行目は 1 行目の後に" "$tmp/Str.tla" "$tmp/neg.jsonl"
check "str --all" 0 "適合" --all "$tmp/Str.tla" "$tmp/str.jsonl"
check "neg --all" 1 "2 行目は 1 行目の後に" --all "$tmp/Str.tla" "$tmp/neg.jsonl"
# --all: 長い値で TLC が状態を折り返しても、ずれを TLC のエラーと取り違えない
long="$(python3 -c 'import json; print(json.dumps([{"who":"a","ok":True}]*40))')"
printf '{"count":0,"served":0,"log":[]}\n{"count":0,"served":0,"log":%s}\n' "$long" >"$tmp/longv.jsonl"
run_all 1 longv "2 行目は 1 行目の後に"

# 生成した trace spec は spec の隣に残さない(tasks/loopeng を汚さない)
if [ -n "$(find "$tmp" -maxdepth 1 -name '*_Trace*')" ]; then ng "$(msg left)"; else ok "$(msg not_left)"; fi

check "--selfcheck" 0 "" --selfcheck

exit "$fail"
