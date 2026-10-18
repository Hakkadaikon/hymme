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
# grep が無い PATH では判定できないので、通さずに exit 2
mkdir -p "$tmp/nogrep"
for c in bash cat dirname basename tail mktemp rm; do ln -s "$(command -v "$c")" "$tmp/nogrep/$c"; done
ln -s "$(command -v sany)" "$tmp/nogrep/sany"
lint 2 Undef "$tmp/nogrep"

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

# 並列に回しても、変異ごとの結果と集計は1本ずつ回したときと同じ
results() { # results <spec> <jobs>: 変異ごとの判定行(並び順込み)と集計行
  (cd "$tmp" && python3 "$root/loopeng/bin/tla_mutate_oracle.py" "$1.tla" --jobs "$2" --mut-timeout 20 2>&1) |
    grep -E '^  (killed|SURVIVOR|invalid|UNVERIFIED) |^mutants:' || true
}
serial="$(results Good 1)"
parallel="$(results Good 4)"
if [ -n "$serial" ] && [ "$serial" = "$parallel" ]; then
  ok 'oracle --jobs 4 matches --jobs 1'
else
  ng 'oracle --jobs 4 differs from --jobs 1'
  diff <(echo "$serial") <(echo "$parallel") | head -10
fi
if [ -e "$tmp/states" ]; then ng 'oracle left a states/ directory next to the spec'; else ok 'oracle keeps TLC scratch out of the spec directory'; fi

# 違反のたびに TLC が書く *_TTrace_* も spec の隣に残さない
if ls "$tmp"/*_TTrace_* >/dev/null 2>&1; then ng 'oracle left *_TTrace_* files next to the spec'; else ok 'oracle leaves no *_TTrace_* files'; fi

# --since: 変えた行だけに変異を入れる
mkdir -p "$tmp/since"
cp "$tmp/Good.tla" "$tmp/Good.cfg" "$tmp/since/"
g() { git -C "$tmp/since" -c user.email=t@t -c user.name=t "$@"; }
g init -q
g add Good.tla Good.cfg
g commit -q -m base
since() { # since <want-exit> <want-mutants|-> [説明]: --since HEAD の終了コードと変異の数
  local got=0 out
  out="$(cd "$tmp/since" && python3 "$root/loopeng/bin/tla_mutate_oracle.py" Good.tla --since HEAD --mut-timeout 20 2>&1)" || got=$?
  if [ "$got" -eq "$1" ] && { [ "$2" = - ] || grep -qE "^mutants: $2 " <<<"$out"; }; then
    ok "oracle --since ${3:-HEAD} -> exit $got, $2 mutants"
  else
    ng "oracle --since ${3:-HEAD}: exit $got (want $1), want $2 mutants"
    grep -E '^mutants:|changed|since|Error|error' <<<"$out" || true
  fi
}
since 0 0 '(no change)'
# ユーザーの git 設定で色や外部 diff が付いても、変えた行を読める
g config color.ui always
# Next の行だけを変える: 4か所に変異が入る。x < 1 の上限は Inv より狭いので、上限を緩める変異は
# 生き残る(survivor ありの終了コード 1 が正しい)
sed -i "s/^Next == .*/Next == x < 1 \/\\\\ x' = x + 1/" "$tmp/since/Good.tla"
since 1 4 '(Next changed, color.ui=always)'
# 4か所とも Next の行に入っている
next_ok="$({ cd "$tmp/since" && python3 "$root/loopeng/bin/tla_mutate_oracle.py" Good.tla --since HEAD --mut-timeout 20 2>&1 || true; } |
  python3 -c 'import re,sys; src=open(sys.argv[1]).read(); lo=src.index("Next =="); hi=src.index("\n",lo)
offs=[int(m) for m in re.findall(r"^  (?:killed|SURVIVOR|invalid|UNVERIFIED)\s+\S+@(\d+)\s*$", sys.stdin.read(), re.M)]
print("yes" if len(offs)==4 and all(lo<=o<hi for o in offs) else "no")' "$tmp/since/Good.tla")"
if [ "$next_ok" = yes ]; then ok 'oracle --since mutates only the Next line'; else ng 'oracle --since mutated outside the Next line'; fi
# 行を消しただけなら、変異を入れる行は無い
g checkout -q -- Good.tla
sed -i '/^Inv == /d' "$tmp/since/Good.tla"
printf 'INIT Init\nNEXT Next\n' >"$tmp/since/Good.cfg"
since 0 0 '(a line deleted)'
g checkout -q -- Good.tla Good.cfg
# git 管理外の spec は、全行を変えた行として扱う(何も回さずに合格にしない)
sed 's/MODULE Good/MODULE New/' "$tmp/since/Good.tla" >"$tmp/since/New.tla"
cp "$tmp/since/Good.cfg" "$tmp/since/New.cfg"
got=0
out="$(cd "$tmp/since" && python3 "$root/loopeng/bin/tla_mutate_oracle.py" New.tla --since HEAD --mut-timeout 20 2>&1)" || got=$?
if grep -qE '^mutants: 5 ' <<<"$out"; then ok 'oracle --since treats an untracked spec as all new'; else ng "oracle --since on an untracked spec: exit $got"; grep -E '^mutants:' <<<"$out" || true; fi
# リビジョンが無い、git の外: ベースラインを回す前に、専用の終了コード 4 で止める
bad() { # bad <説明> <dir> <rev>
  local got=0
  (cd "$2" && python3 "$root/loopeng/bin/tla_mutate_oracle.py" Good.tla --since "$3" --mut-timeout 20 >/dev/null 2>&1) || got=$?
  if [ "$got" -eq 4 ]; then ok "oracle --since $1 -> 4"; else ng "oracle --since $1: exit $got (want 4)"; fi
}
bad 'with a missing revision' "$tmp/since" no-such-rev
mkdir -p "$tmp/nogit" && cp "$tmp/Good.tla" "$tmp/Good.cfg" "$tmp/nogit/"
bad 'outside git' "$tmp/nogit" HEAD

exit "$fail"
