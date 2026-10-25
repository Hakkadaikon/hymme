#!/usr/bin/env bash
# verifiability.py(検証容易性の指標)と hooks/verifiability-gate.sh の回帰テスト。
# 要: lizard を import できる python3 が PATH にあること(flake の checks が用意する)。
set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

ok() { echo "ok   $1"; }
ng() { echo "FAIL $1"; fail=1; }

mkdir -p "$tmp/src" "$tmp/tasks/verifiability"
cat >"$tmp/src/rules.py" <<'EOF'
import time

CACHE = {}


def allowed(age, country, banned):
    if age < 18:
        return False
    return country not in banned


def tangled(user, rule, now, flags, seg, extra):
    if rule.get("a"):
        if user.get("x"):
            return True
        elif user.get("y"):
            return False
    if rule.get("b") and user.get("z"):
        return True
    if rule.get("c") or user.get("w"):
        return False
    for f in flags:
        if f in seg:
            return True
    if rule.get("d"):
        return now > 3
    if rule.get("e"):
        return extra
    return False


def stamped(rule):
    return rule.get("t", 0) < time.time()


def cached(key):
    return key in CACHE


def folded(segments, name, uid):
    try:
        return uid in segments[name]
    except KeyError:
        return False


def is_ok(x):
    return x < time.time()


def ok(x):
    return x > 1


def five(a, b, c, d, e):
    return a


def six(a, b, c, d, e, f):
    return a


def branchy(v):
    if v == 1:
        return 1
    if v == 2:
        return 2
    if v == 3:
        return 3
    if v == 4:
        return 4
    if v == 5:
        return 5
    if v == 6:
        return 6
    if v == 7:
        return 7
    if v == 8:
        return 8
    if v == 9:
        return 9
    if v == 10:
        return 10
    return 0


class A:
    def check(self, a, b, c, d, e):
        return a


class B:
    def check(self, x):
        try:
            return x in CACHE
        except KeyError:
            return False
EOF
python3 - "$tmp/src/rules.py" <<'PY'
import sys
body = "\n".join(f"    x{i} = {i}" for i in range(55))
open(sys.argv[1], "a").write(f"\n\ndef longest():\n{body}\n    return 0\n")
PY
printf 'fun decide(a: Int): Boolean {\n    return a > 1\n}\n' >"$tmp/src/K.kt"
printf 'import time as t\n\n\ndef aliased(x):\n    return x < t.time()\n\n\ndef notmethod(self, a, b, c, d, e):\n    return a\n' >"$tmp/src/alias.py"
printf 'class Rules {\n  boolean check(int a) { return a > 1; }\n}\nclass Other {\n  boolean check(int a) { return a < 1; }\n}\n' >"$tmp/src/Rules.java"
cat >"$tmp/src/rules.js" <<'EOF'
function pure(a, b) {
  return a > b;
}
function clocky(a) {
  return a < Date.now();
}
function swallow(s, k) {
  try { return s[k].ok; } catch (e) { return false; }
}
EOF
mkdir -p "$tmp/bin"
# shebang の /usr/bin/env が無い sandbox(Linux の nix build)でも動くよう、PATH に置く道具は /bin/sh で包む
printf '#!/bin/sh\nexec python3 "%s/loopeng/bin/verifiability.py" "$@"\n' "$root" >"$tmp/bin/verifiability.py"
chmod +x "$tmp/bin/verifiability.py"

ledger() { # ledger <name> <body>  (レビュー合格済みの行を末尾に付ける)
  printf '# 検証容易性台帳: %s\n\n%s\n\n## レビュー\n\n- [x] レビュー合格: 2026-10-25 「合格」\n' "$1" "$2" >"$tmp/tasks/verifiability/$1.md"
}
ledger Good '## 対象

- src/rules.py::allowed
- src/rules.js::pure'
ledger Ccn '## 対象

- src/rules.py::branchy'
ledger Nloc '## 対象

- src/rules.py::longest'
ledger Args '## 対象

- src/rules.py::six'
ledger ArgsOk '## 対象

- src/rules.py::five
- src/rules.py::A.check'
ledger Suffix '## 対象

- src/rules.py::ok'
ledger Ambiguous '## 対象

- src/rules.py::check'
ledger Method '## 対象

- src/rules.py::B.check'
ledger JsFold '## 対象

- src/rules.js::swallow'
ledger Kotlin '## 対象

- src/K.kt::decide'
ledger KotlinWaived '## 対象

- src/K.kt::decide

## 例外

- src/K.kt::decide 副作用: 判定は引数だけを読む(目で確認)
- src/K.kt::decide エラーを真偽値に畳む: 例外処理を持たない(目で確認)'
ledger WaiveOther '## 対象

- src/rules.py::stamped
- src/rules.py::allowed

## 例外

- src/rules.py::allowed 副作用: 別の対象への例外は効かない'
ledger WaiveWrongMetric '## 対象

- src/rules.py::tangled

## 例外

- src/rules.py::tangled 副作用: 指標が違えば CCN の超過は残る'
ledger UnknownMetric '## 対象

- src/rules.py::stamped

## 例外

- src/rules.py::stamped 速度: そんな指標は無い'
ledger Alias '## 対象

- src/alias.py::aliased'
ledger SelfFn '## 対象

- src/alias.py::notmethod'
ledger JavaDot '## 対象

- src/Rules.java::Rules.check'
ledger NoFile '## 対象

- src/nosuch.py::f'
ledger Outside '## 対象

- /etc/hosts::f'
ledger DotDot '## 対象

- ../../../../../../../../etc/hosts::f'
ln -s /etc/hosts "$tmp/src/link.py"
ledger Symlink '## 対象

- src/link.py::f'
ledger PostImpl '## 対象

対象コード無し(実装後): 外部チームのサービスで、手元にはログしか無い'
# テンプレの雛形行を消し忘れても、「## 対象」の外にある行は対象に数えない
printf '# 検証容易性台帳: NoCodeTmpl\n\n## 対象\n\n対象コード無し: 設計のみ\n\n## 例外\n\n例: `- src/rules.py::decide 副作用: 理由`\n' >"$tmp/tasks/verifiability/NoCodeTmpl.md"
printf '# 検証容易性台帳: NoSection\n\n- src/rules.py::allowed\n' >"$tmp/tasks/verifiability/NoSection.md"
ledger Impure '## 対象

- src/rules.py::stamped
- src/rules.py::cached
- src/rules.js::clocky'
ledger Fold '## 対象

- src/rules.py::folded
- src/rules.js::swallow'
ledger Waived '## 対象

- src/rules.py::stamped

## 例外

- src/rules.py::stamped 副作用: 時刻は呼び出し側で固定値に差し替えて検証する'
ledger Missing '## 対象

- src/rules.py::nosuch'
ledger NoCode '## 対象

対象コード無し: 実装前の設計検証のため'
ledger Empty '## 対象
'
ledger BadWaiver '## 対象

- src/rules.py::stamped

## 例外

- src/rules.py::stamped 副作用:'

run() { # run <want-exit> <ledger> [want-substring]
  local got=0
  (cd "$tmp" && python3 "$root/loopeng/bin/verifiability.py" "tasks/verifiability/$2.md") >"$tmp/out" 2>&1 || got=$?
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

cp "$tmp/tasks/verifiability/Good.md" "$tmp/tasks/verifiability/NoReview.md"
sed -i.bak 's/- \[x\] レビュー合格/- [ ] レビュー合格/' "$tmp/tasks/verifiability/NoReview.md"
printf '# 検証容易性台帳: NoCodeNoReview\n\n## 対象\n\n対象コード無し: 設計のみ\n' >"$tmp/tasks/verifiability/NoCodeNoReview.md"

run 0 Good "PASS"
run 1 Ccn "CCN 11 > 10"
run 1 Nloc "> 50"
run 1 Args "引数 6 > 5"
run 0 ArgsOk "PASS src/rules.py::A.check"
run 0 Suffix "PASS src/rules.py::ok"
run 2 Ambiguous "Class.method"
run 1 Method "module-level CACHE"
run 1 Method "エラーを真偽値に畳む: line"
run 1 JsFold "catch/recover returns a bool"
run 1 Kotlin ".kt は測れない"
run 0 KotlinWaived "例外"
run 1 WaiveOther "FAIL src/rules.py::stamped"
run 1 WaiveWrongMetric "CCN 12 > 10"
run 2 UnknownMetric "速度"
run 2 NoFile "ファイルが無い"
run 2 NoSection "## 対象"
run 1 Alias "imported t"
run 1 SelfFn "引数 6 > 5"
run 0 JavaDot "PASS src/Rules.java::Rules.check"
run 2 Outside "相対パス"
run 2 DotDot "相対パス"
run 2 Symlink "相対パス"
run 0 PostImpl "対象コード無し"
run 1 Impure "time."
run 1 Impure "CACHE"
run 1 Impure "Date.now"
run 1 Fold "エラーを真偽値に畳む"
run 0 Waived "例外"
run 2 Missing "nosuch"
run 0 NoCode "対象コード無し"
run 2 Empty "対象"
run 2 BadWaiver "理由"

# --- hook: 検証の入口を台帳と指標で止める ---
gate() { # gate <want-exit> <command> [cwd]
  local got=0
  printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$2")" \
    | (cd "${3:-$tmp}" && PATH="$tmp/bin:$PATH" bash "$root/hooks/verifiability-gate.sh") >"$tmp/gate.out" 2>&1 || got=$?
  if [ "$got" -eq "$1" ]; then ok "gate '$2' -> $got"; else ng "gate '$2': exit $got (want $1)"; cat "$tmp/gate.out"; fi
}

gate 0 'loop-middle SPEC=Good'
gate 2 'loop-middle SPEC=Ccn'
gate 2 'loop-outer SPEC=Absent'
gate 0 'loop-inner SPEC=NoCode'
gate 2 'loop-middle SPEC=NoReview'
gate 0 'loop-middle SPEC=NoCodeNoReview'
gate 2 'make -f x/Makefile.loopeng loop-middle SPEC=Fold'
gate 0 'smt_oracle.py tasks/loopeng/Good.smt.py'
gate 2 'smt_oracle.py tasks/loopeng/Impure.smt.py'
gate 2 'python3 /opt/bin/smt_oracle.py tasks/loopeng/Absent.smt.py'
gate 0 'trace_check.py tasks/loopeng/Waived.tla run.jsonl'
gate 2 'trace_check.py tasks/loopeng/Ccn.tla run.jsonl'
mkdir -p "$tmp/tasks/fv/Fold" "$tmp/tasks/fv/Good"
gate 2 'lake build' "$tmp/tasks/fv/Fold"
gate 0 'lake build' "$tmp/tasks/fv/Good"
gate 2 'cd tasks/fv/Fold && lake build'
gate 0 'lake build'
# オプションや前置きが先に来ても、連結されていても入口を見つける
gate 2 'trace_check.py --all tasks/loopeng/Ccn.tla run.jsonl'
gate 2 'trace_check.py --cfg x.cfg --timeout 5 tasks/loopeng/Ccn.tla run.jsonl'
gate 2 'smt_oracle.py --timeout 5000 tasks/loopeng/Impure.smt.py'
gate 2 '/usr/bin/python3 -I /x/trace_check.py tasks/loopeng/Ccn.tla r.jsonl'
gate 2 'nix develop /h -c trace_check.py tasks/loopeng/Ccn.tla r.jsonl'
gate 2 'timeout 600 smt_oracle.py tasks/loopeng/Impure.smt.py'
gate 2 'FOO=1 loop-middle SPEC=Ccn'
gate 2 'cd tasks/loopeng && trace_check.py Ccn.tla r.jsonl'
gate 2 'loop-middle SPEC=Good && loop-middle SPEC=Ccn'
gate 2 'export TMPDIR=/tmp && cd tasks/fv/Fold && lake build'
gate 2 'ELAN_HOME=x lake build' "$tmp/tasks/fv/Fold"
gate 2 "cd $tmp/tasks/fv/Fold && lake build" /
gate 0 'trace_check.py --all tasks/loopeng/Good.tla run.jsonl'
# 改行・サブシェル・予約語・bash -c・各種オプションでも入口を見つける
gate 2 $'cd tasks/fv/Fold\nlake build'
gate 2 '(cd tasks/fv/Fold && lake build)'
gate 2 'if smt_oracle.py tasks/loopeng/Impure.smt.py; then echo ok; fi'
gate 2 "bash -c 'loop-middle SPEC=Ccn'"
gate 2 'timeout -k 5 60 trace_check.py tasks/loopeng/Ccn.tla r.jsonl'
gate 2 'python3 -W ignore /x/smt_oracle.py tasks/loopeng/Impure.smt.py'
gate 2 'lake -d tasks/fv/Fold build'
gate 2 'make -C tasks/loopeng -f x/Makefile.loopeng loop-middle SPEC=Fold'
gate 2 'trace_check.py tasks/loopeng/Ccn.tla r.jsonl --all'
# 環境変数の SPEC も make に届く
gate 2 'SPEC=Ccn make -f x/Makefile.loopeng loop-outer'
gate 2 'export SPEC=Ccn; make -f x/Makefile.loopeng loop-outer'
# オプション付きの前置き
gate 2 'nice -n 10 loop-middle SPEC=Ccn'
gate 2 'sudo -E loop-middle SPEC=Ccn'
gate 2 'time -p loop-middle SPEC=Ccn'
gate 2 'bash -e -c "loop-middle SPEC=Ccn"'
gate 2 'bash --norc -c "loop-middle SPEC=Ccn"'
gate 2 'nix develop /h --command bash -c "loop-middle SPEC=Ccn"'
gate 2 'bash -lc "loop-middle SPEC=Ccn"'
gate 2 'bash -euo pipefail -c "loop-middle SPEC=Ccn"'
gate 2 'fish -c "loop-middle SPEC=Ccn"'
# シェルが読む heredoc の本文は実行される
gate 2 $'bash <<\'EOF\'\nloop-middle SPEC=Ccn\nEOF'
gate 2 $'cat <<EOF | sh\nloop-middle SPEC=Ccn\nEOF'
# heredoc の開始行の後ろにあるコマンドは本文ではない
gate 2 $'cat > x.txt <<EOF && loop-middle SPEC=Ccn\nbody\nEOF'
# 先頭のリダイレクト、SPEC 省略(既定の Spec)、make のディレクトリ指定の別表記、lake --dir=
gate 2 '> log.txt loop-middle SPEC=Ccn'
gate 2 '2>&1 loop-middle SPEC=Ccn'
gate 2 'make -f x/Makefile.loopeng loop-middle'
gate 2 'make -Ctasks/loopeng -f x/Makefile.loopeng loop-middle SPEC=Fold'
gate 2 'make --directory=tasks/loopeng -f x/Makefile.loopeng loop-middle SPEC=Fold'
gate 2 'lake --dir=tasks/fv/Fold build'
# $(…) の中の cd は外に漏れない
gate 2 'echo $(cd / && ls) && loop-middle SPEC=Ccn'
# シングルクォートの中のバッククォートは文字列。変数の SPEC は決まらないので止める
gate 0 "git commit -m 'docs: run \`loop-middle SPEC=Ccn\` first'"
gate 2 'for s in a b; do loop-middle SPEC=$s; done'
# ダブルクォートの中のアポストロフィはクォートの開始ではない。エスケープした \` と \$( は文字列
gate 2 $'echo "don\'t" "$(loop-middle SPEC=Ccn)"'
gate 0 'git commit -m "docs: mention \`trace_check.py\`"'
gate 0 'git commit -m "fix: \$(loop-middle) docs"'
# クォートしない heredoc の本文は $(…) を展開する
gate 2 $'cat > n <<EOF\n$(loop-middle SPEC=Ccn)\nEOF'
# シェルや python の標準入力に流す形
gate 2 'bash <<< "loop-middle SPEC=Ccn"'
gate 2 "echo 'loop-middle SPEC=Ccn' | bash"
gate 2 $'python3 - <<\'EOF\'\nimport os; os.system("loop-middle SPEC=Ccn")\nEOF'
gate 2 "echo 'loop-middle SPEC=Ccn' | python3"
gate 0 "echo '{}' | python3 -m json.tool"
# heredoc の本文ではクォートはただの文字(it's の後の $(…) も展開される)
gate 2 $'cat <<EOF\nit\'s $(loop-middle SPEC=Ccn)\nEOF'
# python3 -m はモジュールを動かすだけで、標準入力をスクリプトとして読まない
gate 0 'cat x.json | python3 -m json.tool && loop-middle SPEC=Good'
gate 0 'echo "loop-middle SPEC=Ccn" | python3 -m json.tool'
gate 0 $'cat <<\'EOF\' | python3 -m json.tool\n{"cmd": "loop-middle SPEC=Ccn"}\nEOF'
# 標準入力の判定はパイプで渡ってくる直前の区切りだけを見る
gate 0 $'bash <<\'EOF\'\necho hi\nEOF\nloop-middle SPEC=Good'
gate 0 'echo hi | python3 && loop-middle SPEC=Good'
# tasks/fv を使っていないリポジトリでは、変数を含む cd の後の lake build を止めない
plain="$(mktemp -d)"
gate 0 'cd "$HOME/proj" && lake build' "$plain"
gate 2 'cd "$HOME/proj" && lake build' "$tmp/src"
rmdir "$plain"
# 変数を含む cd の先の lake build は台帳を特定できない
gate 2 'cd $D && lake build'
# コミットメッセージの本文(heredoc)に入口の語があっても、それは文字列なので止めない
gate 0 $'git commit -m "$(cat <<\'EOF\'\nfeat(loopeng): add trace_check.py and lake build notes\nloop-middle SPEC=Ccn\nEOF\n)"'
# 中身を読めない形に入口の語があれば止める。ただの文字列としての言及は止めない
gate 2 'echo tasks/loopeng/Ccn.tla | xargs trace_check.py'
gate 2 'eval "loop-middle SPEC=Ccn"'
gate 2 'echo $(smt_oracle.py tasks/loopeng/Impure.smt.py)'
gate 2 $'python3 -c \'import os; os.system("loop-middle SPEC=Ccn")\''
gate 0 'grep -n trace_check.py README.md'
gate 2 'trace_check.py "tasks/loopeng/Bad Name.tla" r.jsonl'
# 実ログの突き合わせは実装後の段: ただの「対象コード無し」は止め、「(実装後)」と理由があれば通す
gate 2 'trace_check.py tasks/loopeng/NoCode.tla r.jsonl'
gate 0 'trace_check.py tasks/loopeng/PostImpl.tla r.jsonl'
gate 0 'loop-middle SPEC=PostImpl'
gate 0 'loop-middle SPEC=NoCodeTmpl'
# hook 入力の cwd を作業ディレクトリとして使う
got=0
printf '{"cwd":"%s","tool_input":{"command":"lake build"}}' "$tmp/tasks/fv/Fold" | (cd / && PATH="$tmp/bin:$PATH" bash "$root/hooks/verifiability-gate.sh") >"$tmp/gate.out" 2>&1 || got=$?
if [ "$got" -eq 2 ]; then ok "gate uses the payload cwd"; else ng "payload cwd: exit $got"; cat "$tmp/gate.out"; fi
gate 0 'echo loop-middle SPEC=Ccn'
gate 0 'grep smt_oracle.py README.md'
gate 2 'loop-middle'  # SPEC 省略は Makefile.loopeng の既定 Spec

# 指標の道具が無い環境では止める(検証の入口を素通りさせない)
mkdir -p "$tmp/nobin"
for c in bash cat grep awk sed head cut dirname basename python3; do ln -s "$(command -v "$c")" "$tmp/nobin/$c"; done
got=0
printf '{"tool_input":{"command":"loop-middle SPEC=Good"}}' | (cd "$tmp" && PATH="$tmp/nobin" bash "$root/hooks/verifiability-gate.sh") >"$tmp/gate.out" 2>&1 || got=$?
if [ "$got" -eq 2 ] && grep -q 'verifiability.py' "$tmp/gate.out"; then ok "gate blocks without verifiability.py"; else ng "gate without tool: exit $got"; cat "$tmp/gate.out"; fi
# 写すコードが無い台帳は、計測の道具が無くても通す
got=0
printf '{"tool_input":{"command":"loop-middle SPEC=NoCodeNoReview"}}' | (cd "$tmp" && PATH="$tmp/nobin" bash "$root/hooks/verifiability-gate.sh") >"$tmp/gate.out" 2>&1 || got=$?
if [ "$got" -eq 0 ]; then ok "no-code ledger passes without verifiability.py"; else ng "no-code without tool: exit $got"; cat "$tmp/gate.out"; fi
# 作業中のリポジトリに json.py があっても hook はそれを読み込まない
printf 'raise SystemExit(0)\n' >"$tmp/json.py"
gate 2 'loop-middle SPEC=Ccn'
rm "$tmp/json.py"

# python3 が無く解析できないときは、入口らしき語があれば止め、無ければ通す
mkdir -p "$tmp/nopy"
for c in bash cat grep awk sed head cut dirname basename; do ln -s "$(command -v "$c")" "$tmp/nopy/$c"; done
for c in "2 loop-middle SPEC=Good" "0 ls -la"; do
  set -- $c
  got=0
  printf '{"tool_input":{"command":"%s"}}' "${*:2}" | (cd "$tmp" && PATH="$tmp/nopy" bash "$root/hooks/verifiability-gate.sh") >"$tmp/gate.out" 2>&1 || got=$?
  if [ "$got" -eq "$1" ]; then ok "no python3: '${*:2}' -> $got"; else ng "no python3 '${*:2}': exit $got (want $1)"; cat "$tmp/gate.out"; fi
done

python3 loopeng/bin/verifiability.py --selfcheck >/dev/null && ok "--selfcheck" || ng "--selfcheck"

exit "$fail"
