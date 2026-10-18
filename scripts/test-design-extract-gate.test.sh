#!/usr/bin/env bash
# hooks/test-design-extract-gate.sh の回帰テスト。要: python3, git。
set -euo pipefail

cd "$(dirname "$0")/.."
hook="$PWD/hooks/test-design-extract-gate.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

ok() { echo "ok   $1"; }
ng() {
  echo "FAIL $1"
  fail=1
}

# ledger <名前> <行...>: 作業ディレクトリの tasks/test-design/<名前>.md を作る
ledger() {
  local name="$1"
  shift
  mkdir -p tasks/test-design
  printf '%s\n' "# 台帳: $name" "$@" >"tasks/test-design/$name.md"
}

# gate <want-exit> <説明> <file_path>
gate() {
  local got=0
  printf '{"tool_input":{"file_path":"%s"}}' "$3" | bash "$hook" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$1" ]; then ok "$2 -> $got"; else ng "$2: exit $got (want $1)"; fi
}

# 各ケースは空の作業ディレクトリ(git リポジトリ)から始める
fresh() {
  rm -rf "$tmp/w" "$tmp/other"
  mkdir -p "$tmp/w"
  cd "$tmp/w"
  git init -q
}

fresh
gate 0 '台帳が無ければ通す' 'src/a_test.py'

fresh
ledger product '## 台帳' '- [ ] T-001 x'
gate 2 '対象を書いていない未完の台帳は、どのテストも止める' 'scripts/x_test.py'
gate 0 'テストファイルでなければ通す' 'src/a.rs'

fresh
ledger product 'テスト対象: crates/*' '## 台帳' '- [ ] T-001 x'
gate 0 '対象外のテストは、未完の台帳があっても通す' 'scripts/metrics_test.py'
gate 2 '対象のテストは、未完の台帳なら止める' 'crates/webqa/tests/run_test.rs'
gate 2 '絶対パスでも対象として扱う' "$tmp/w/crates/webqa/tests/run_test.rs"
mkdir -p crates/webqa
(cd crates/webqa && gate 2 'サブディレクトリからの相対パスでも対象として扱う' 'tests/run_test.rs')
(cd crates/webqa && gate 0 'サブディレクトリからの相対パスで対象外なら通す' '../../scripts/x_test.py')

fresh
ledger product 'テスト対象: crates/*' '## 台帳' '- [ ] T-001 x'
ledger tool 'テスト対象: scripts/metrics_test.py scripts/other_test.py' '## 台帳' '- [x] T-001 x' '- [x] T-002 y'
gate 0 '完了した台帳の対象は、別の台帳が未完でも通す' 'scripts/metrics_test.py'
gate 0 '対象を複数書ける' 'scripts/other_test.py'

fresh
ledger tool 'テスト対象: scripts/*' '## 台帳' '- [x] T-001 x' '- [x] T-003 z'
gate 2 '対象の台帳に欠番があれば止める' 'scripts/metrics_test.py'

fresh
ledger tool 'テスト対象: scripts/*' '## 台帳' '- [x] T-001 x'
mkdir -p tasks/loopeng
touch tasks/loopeng/Spec.feature
gate 2 '.feature がどの台帳にも転記されていなければ止める' 'scripts/metrics_test.py'
ledger product 'テスト対象: crates/*' '出典: Spec.feature' '## 台帳' '- [ ] T-001 x'
gate 0 '.feature が転記済みなら、対象外の台帳の未完では止めない' 'scripts/metrics_test.py'

fresh
ledger product '## 台帳' '- [ ] T-001 x'
mkdir -p "$tmp/other/scripts"
git -C "$tmp/other" init -q
gate 0 '別のリポジトリのテストは、そのリポジトリの台帳だけを見る' "$tmp/other/scripts/a.test.sh"
mkdir -p "$tmp/other/tasks/test-design"
printf '%s\n' '## 台帳' '- [ ] T-001 x' >"$tmp/other/tasks/test-design/t.md"
gate 2 '別のリポジトリにある未完の台帳では止める' "$tmp/other/scripts/a.test.sh"

fresh
ledger product 'テスト対象: crates/*' '## 台帳' '- [ ] T-001 x'
ln -s "$tmp/w" "$tmp/link"
gate 2 'シンボリックリンク経由の絶対パスでも対象として扱う' "$tmp/link/crates/a_test.rs"
rm "$tmp/link"
gate 0 '絶対パスで対象外なら通す' "$tmp/w/scripts/a_test.py"

fresh
ledger product 'テスト対象: <この台帳が受け持つテストファイルの glob。例: crates/*>' '## 台帳' '- [ ] T-001 x'
gate 2 'テンプレートのままの対象行は、未記入として全テストに効かせる' 'scripts/x_test.py'

fresh
ledger product 'テスト対象：crates/*' '## 台帳' '- [ ] T-001 x'
gate 0 '全角コロンの対象行も読む' 'scripts/x_test.py'

fresh
ledger product 'テスト対象: crates/*' 'テスト対象: tools/*' '## 台帳' '- [ ] T-001 x'
gate 2 '対象行を複数書ける' 'tools/x_test.py'

rm -rf "$tmp/nogit"
mkdir -p "$tmp/nogit"
cd "$tmp/nogit"
ledger product '## 台帳' '- [ ] T-001 x'
gate 2 'git の外では作業ディレクトリの台帳を見る' 'x_test.py'

exit "$fail"
