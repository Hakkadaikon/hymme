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

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    ok) printf '合格   %s\n' "$2" ;;
    ng) printf '不合格 %s\n' "$2" ;;
    want_exit) printf '%s: exit %s(期待は %s)' "$2" "$3" "$4" ;;
    summary) printf '%s、要約: %s' "$2" "$3" ;;
    gate_warns) printf 'lint を実行できないとき、ゲートは警告して通す' ;;
    gate_no_warn) printf 'ゲートが lint を実行できない分岐に届いていない' ;;
    jobs_same) printf 'oracle --jobs 4 の結果が --jobs 1 と同じ' ;;
    jobs_differ) printf 'oracle --jobs 4 の結果が --jobs 1 と違う' ;;
    states_left) printf 'oracle が spec の隣に states/ を残した' ;;
    states_clean) printf 'oracle は TLC の作業ディレクトリを spec の隣に作らない' ;;
    ttrace_left) printf 'oracle が spec の隣に *_TTrace_* を残した' ;;
    ttrace_clean) printf 'oracle は *_TTrace_* を残さない' ;;
    since_ok) printf 'oracle --since %s -> exit %s、変異 %s 個' "$2" "$3" "$4" ;;
    since_ng) printf 'oracle --since %s: exit %s(期待は %s)、変異は %s 個のはず' "$2" "$3" "$4" "$5" ;;
    next_only) printf 'oracle --since は Next の行だけに変異を入れる' ;;
    next_outside) printf 'oracle --since が Next の行の外に変異を入れた' ;;
    untracked_ok) printf 'oracle --since は git 管理外の spec を全行新規として扱う' ;;
    untracked_ng) printf 'oracle --since(git 管理外の spec): exit %s' "$2" ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}
ok() { msg ok "$1"; }
ng() {
  msg ng "$1"
  fail=1
}
spec() { printf '%s\n' "---- MODULE $1 ----" "${@:2}" "====" >"$tmp/$1.tla"; }

spec Good 'EXTENDS Naturals' 'VARIABLE x' 'Init == x = 0' "Next == x < 2 /\\ x' = x + 1" 'Inv == x <= 2'
spec Undef 'VARIABLE x' 'Init == x = 0' "Next == x' = y"
spec Syn 'VARIABLE x' 'Init == x = = 0'
spec Typed 'EXTENDS Naturals' 'VARIABLE' '  \* @type: Int;' '  x' 'Init == x = 0' "Next == x' = x + 1"
spec TyBad 'EXTENDS Naturals' 'VARIABLE' '  \* @type: Int;' '  x' 'Init == x = 0' "Next == x' = TRUE"
# eq->neq を EXCEPT の中に当てると構文エラーの mutant になる
spec Exc 'VARIABLE f' 'Init == f = [i \in {1} |-> 0]' "Next == f' = [f EXCEPT ![1] = 2]" 'Inv == f[1] \in {0, 2}'
printf 'INIT Init\nNEXT Next\nINVARIANT Inv\n' >"$tmp/Good.cfg"
cp "$tmp/Good.cfg" "$tmp/Exc.cfg"
mkdir -p "$tmp/sub" && cp "$tmp/Undef.tla" "$tmp/sub/"

# sany も java も無い PATH(lint が使うコマンドだけを置く)
mkdir -p "$tmp/nosany"
for c in bash cat grep dirname basename tail mktemp rm python3; do ln -s "$(command -v "$c")" "$tmp/nosany/$c"; done
# 型検査の前に落ちる偽の apalache-mc
mkdir -p "$tmp/stub"
printf '#!/bin/sh\necho "launcher exploded" >&2\nexit 1\n' >"$tmp/stub/apalache-mc"
chmod +x "$tmp/stub/apalache-mc"

lint() { # lint <want-exit> <spec> [PATH]
  local got=0
  PATH="${3:-$PATH}" bash loopeng/bin/tla_lint.sh "$tmp/$2.tla" >"$tmp/lint.out" 2>&1 || got=$?
  if [ "$got" -eq "$1" ]; then ok "lint $2 -> $got"; else
    ng "$(msg want_exit "lint $2" "$got" "$1")"
    tail -15 "$tmp/lint.out"
  fi
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
  if [ "$got" -eq "$1" ]; then ok "gate '$2' -> $got"; else ng "$(msg want_exit "gate '$2'" "$got" "$1")"; fi
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
gate 0 'tlc "Undef.tla' # 引用符が閉じていない: 判定できないので通す
gate 0 'broken json' "$PATH" '{not json'
nosany_payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":"tlc Undef.tla"},"cwd":sys.argv[1]}))' "$tmp")"
gate 0 'tlc Undef.tla (no sany)' "$tmp/nosany" "$nosany_payload"
# 通したのが「lint を実行できなかった」分岐であること(spec を特定できずに素通りしたのではないこと)
if printf '%s' "$nosany_payload" | PATH="$tmp/nosany" bash hooks/loopeng-lint-gate.sh 2>&1 >/dev/null | grep -q '静的検査を実行できなかった'; then
  ok "$(msg gate_warns)"
else
  ng "$(msg gate_no_warn)"
fi

oracle() { # oracle <want-exit> <spec> <summary に含むべき ERE> [出力全体に含むべき ERE]
  local got=0 out
  out="$(cd "$tmp" && python3 "$root/loopeng/bin/tla_mutate_oracle.py" "$2.tla" --workers 1 --mut-timeout 20 2>&1)" || got=$?
  local summary
  summary="$(grep '^mutants:' <<<"$out" || true)"
  if [ "$got" -eq "$1" ] && { [ -z "$3" ] || grep -qE "$3" <<<"$summary"; } && { [ -z "${4:-}" ] || grep -qE "$4" <<<"$out"; }; then
    ok "oracle $2 -> $got ${summary}"
  else
    ng "$(msg summary "$(msg want_exit "oracle $2" "$got" "$1")" "${summary:-<なし>}")"
    tail -20 <<<"$out"
  fi
}
# 性質違反だけを killed と数え、TLC の実行時エラーは unverified に分ける(残れば exit 3)
# lt->le#0 は x <= 2 の Inv 違反で落ちる(timeout ではなく性質違反で killed になる行を固定する)
oracle 3 Good 'killed: [1-9].*survivors: 0.*unverified: [1-9]' '^  killed +lt->le#0@'
# 構文エラーになる mutant は invalid に分け、killed に数えない
oracle 3 Exc 'invalid: [1-9]'
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
  ok "$(msg jobs_same)"
else
  ng "$(msg jobs_differ)"
  diff <(echo "$serial") <(echo "$parallel") | head -10
fi
if [ -e "$tmp/states" ]; then ng "$(msg states_left)"; else ok "$(msg states_clean)"; fi

# 違反のたびに TLC が書く *_TTrace_* も spec の隣に残さない
if ls "$tmp"/*_TTrace_* >/dev/null 2>&1; then ng "$(msg ttrace_left)"; else ok "$(msg ttrace_clean)"; fi

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
    ok "$(msg since_ok "${3:-HEAD}" "$got" "$2")"
  else
    ng "$(msg since_ng "${3:-HEAD}" "$got" "$1" "$2")"
    grep -E '^mutants:|changed|since|Error|error' <<<"$out" || true
  fi
}
since 0 0 '(変更なし)'
# ユーザーの git 設定で色や外部 diff が付いても、変えた行を読める
g config color.ui always
# Next の行だけを変える: 4か所に変異が入る。x < 1 の上限は Inv より狭いので、上限を緩める変異は
# 生き残る(survivor ありの終了コード 1 が正しい)
sed -i "s/^Next == .*/Next == x < 1 \/\\\\ x' = x + 1/" "$tmp/since/Good.tla"
since 1 4 '(Next を変更、color.ui=always)'
# 4か所とも Next の行に入っている
next_ok="$({ cd "$tmp/since" && python3 "$root/loopeng/bin/tla_mutate_oracle.py" Good.tla --since HEAD --mut-timeout 20 2>&1 || true; } |
  python3 -c 'import re,sys; src=open(sys.argv[1]).read(); lo=src.index("Next =="); hi=src.index("\n",lo)
offs=[int(m) for m in re.findall(r"^  (?:killed|SURVIVOR|invalid|UNVERIFIED)\s+\S+@(\d+)\s*$", sys.stdin.read(), re.M)]
print("yes" if len(offs)==4 and all(lo<=o<hi for o in offs) else "no")' "$tmp/since/Good.tla")"
if [ "$next_ok" = yes ]; then ok "$(msg next_only)"; else ng "$(msg next_outside)"; fi
# 行を消しただけなら、変異を入れる行は無い
g checkout -q -- Good.tla
sed -i '/^Inv == /d' "$tmp/since/Good.tla"
printf 'INIT Init\nNEXT Next\n' >"$tmp/since/Good.cfg"
since 0 0 '(1 行を削除)'
g checkout -q -- Good.tla Good.cfg
# git 管理外の spec は、全行を変えた行として扱う(何も回さずに合格にしない)
sed 's/MODULE Good/MODULE New/' "$tmp/since/Good.tla" >"$tmp/since/New.tla"
cp "$tmp/since/Good.cfg" "$tmp/since/New.cfg"
got=0
out="$(cd "$tmp/since" && python3 "$root/loopeng/bin/tla_mutate_oracle.py" New.tla --since HEAD --mut-timeout 20 2>&1)" || got=$?
if grep -qE '^mutants: 5 ' <<<"$out"; then ok "$(msg untracked_ok)"; else
  ng "$(msg untracked_ng "$got")"
  grep -E '^mutants:' <<<"$out" || true
fi
# リビジョンが無い、git の外: ベースラインを回す前に、専用の終了コード 4 で止める
bad() { # bad <説明> <dir> <rev>
  local got=0
  (cd "$2" && python3 "$root/loopeng/bin/tla_mutate_oracle.py" Good.tla --since "$3" --mut-timeout 20 >/dev/null 2>&1) || got=$?
  if [ "$got" -eq 4 ]; then ok "oracle --since $1 -> 4"; else ng "$(msg want_exit "oracle --since $1" "$got" 4)"; fi
}
bad '(リビジョンが無い)' "$tmp/since" no-such-rev
mkdir -p "$tmp/nogit" && cp "$tmp/Good.tla" "$tmp/Good.cfg" "$tmp/nogit/"
bad '(git の外)' "$tmp/nogit" HEAD

exit "$fail"
