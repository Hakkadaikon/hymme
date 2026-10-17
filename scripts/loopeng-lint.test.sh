#!/usr/bin/env bash
# tla_lint.sh / hooks/loopeng-lint-gate.sh / tla_mutate_oracle.py の分類の回帰テスト。
# 要: sany, apalache-mc, tlc, python3 が PATH にあること(flake の checks が用意する)。
set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp" _JAVA_OPTIONS="-Djava.io.tmpdir=$tmp"
fail=0

ok()   { echo "ok   $1"; }
ng()   { echo "FAIL $1"; fail=1; }
spec() { printf '%s\n' "---- MODULE $1 ----" "${@:2}" "====" > "$tmp/$1.tla"; }

spec Good  'EXTENDS Naturals' 'VARIABLE x' 'Init == x = 0' "Next == x < 2 /\\ x' = x + 1" 'Inv == x <= 2'
spec Undef 'VARIABLE x' 'Init == x = 0' "Next == x' = y"
spec Syn   'VARIABLE x' 'Init == x = = 0'
spec Typed 'EXTENDS Naturals' 'VARIABLE' '  \* @type: Int;' '  x' 'Init == x = 0' "Next == x' = x + 1"
spec TyBad 'EXTENDS Naturals' 'VARIABLE' '  \* @type: Int;' '  x' 'Init == x = 0' "Next == x' = TRUE"
# eq->neq を EXCEPT の中に当てると構文エラーの mutant になる
spec Exc   'VARIABLE f' 'Init == f = [i \in {1} |-> 0]' "Next == f' = [f EXCEPT ![1] = 2]" 'Inv == f[1] \in {0, 2}'
printf 'INIT Init\nNEXT Next\nINVARIANT Inv\n' > "$tmp/Good.cfg"
cp "$tmp/Good.cfg" "$tmp/Exc.cfg"
mkdir -p "$tmp/sub" && cp "$tmp/Undef.tla" "$tmp/sub/"

# sany も java も無い PATH(lint が使うコマンドだけを置く)
mkdir -p "$tmp/nosany"
for c in bash cat grep dirname basename tail mktemp rm python3; do ln -s "$(command -v "$c")" "$tmp/nosany/$c"; done
# 型検査の前に落ちる偽の apalache-mc
mkdir -p "$tmp/stub"
printf '#!/bin/sh\necho "launcher exploded" >&2\nexit 1\n' > "$tmp/stub/apalache-mc"
chmod +x "$tmp/stub/apalache-mc"

lint() { # lint <want-exit> <spec> [PATH]
  local got=0
  PATH="${3:-$PATH}" bash loopeng/bin/tla_lint.sh "$tmp/$2.tla" >"$tmp/lint.out" 2>&1 || got=$?
  [ "$got" -eq "$1" ] && ok "lint $2 -> $got" || { ng "lint $2: exit $got (want $1)"; tail -15 "$tmp/lint.out"; }
}
lint 0 Good
lint 1 Undef
lint 1 Syn
lint 0 Typed
lint 1 TyBad
lint 2 Missing
lint 2 Good "$tmp/nosany"
lint 2 Typed "$tmp/stub:$PATH"

gate() { # gate <want-exit> <command> [PATH] [raw-payload]
  local got=0 payload
  payload="${4:-$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$2" "$tmp")}"
  printf '%s' "$payload" | PATH="${3:-$PATH}" bash hooks/loopeng-lint-gate.sh >/dev/null 2>&1 || got=$?
  [ "$got" -eq "$1" ] && ok "gate '$2' -> $got" || ng "gate '$2': exit $got (want $1)"
}
gate 2 'tlc Undef.tla'
gate 2 'tlc -workers auto Syn'
gate 2 "cd $tmp && _JAVA_OPTIONS=x tlc -deadlock TyBad.tla 2>&1 | tail"
gate 2 'cd sub && tlc Undef.tla'
gate 2 'java -cp tla2tools.jar tlc2.TLC Undef'
gate 0 'tlc -config Good.cfg Good.tla'
gate 0 'echo tlc Undef.tla'
gate 0 'grep tlc Undef.tla'
gate 0 'tlc NoSuchSpec.tla'
gate 0 'tlc "Undef.tla'                      # 引用符が閉じていない: 判定できないので通す
gate 0 'broken json' "$PATH" '{not json'
nosany_payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":"tlc Undef.tla"},"cwd":sys.argv[1]}))' "$tmp")"
gate 0 'tlc Undef.tla (no sany)' "$tmp/nosany" "$nosany_payload"
# 通したのが「lint を実行できなかった」分岐であること(spec を特定できずに素通りしたのではないこと)
if printf '%s' "$nosany_payload" | PATH="$tmp/nosany" bash hooks/loopeng-lint-gate.sh 2>&1 >/dev/null | grep -q '静的検査を実行できなかった'; then
  ok 'gate warns when lint cannot run'
else
  ng 'gate did not reach the lint-cannot-run branch'
fi

oracle() { # oracle <want-exit> <spec> <summary に含むべき ERE> [出力全体に含むべき ERE]
  local got=0 out
  out="$(cd "$tmp" && python3 "$root/loopeng/bin/tla_mutate_oracle.py" "$2.tla" --workers 1 --mut-timeout 20 2>&1)" || got=$?
  local summary; summary="$(grep '^mutants:' <<<"$out" || true)"
  if [ "$got" -eq "$1" ] && { [ -z "$3" ] || grep -qE "$3" <<<"$summary"; } && { [ -z "${4:-}" ] || grep -qE "$4" <<<"$out"; }; then
    ok "oracle $2 -> $got ${summary}"
  else
    ng "oracle $2: exit $got (want $1), summary: ${summary:-<none>}"; tail -20 <<<"$out"
  fi
}
# 性質違反だけを killed と数え、TLC の実行時エラーは unverified に分ける(残れば exit 3)
# lt->le#0 は x <= 2 の Inv 違反で落ちる(timeout ではなく性質違反で killed になる行を固定する)
oracle 3 Good 'killed: [1-9].*survivors: 0.*unverified: [1-9]' '^  killed +lt->le#0@'
# 構文エラーになる mutant は invalid に分け、killed に数えない
oracle 3 Exc  'invalid: [1-9]'
# ベースラインが通らない spec では mutation を回さない
oracle 2 Undef ''

exit "$fail"
