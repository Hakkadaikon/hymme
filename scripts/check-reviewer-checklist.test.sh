#!/usr/bin/env bash
# check-reviewer-checklist.sh の回帰テスト。fixture は現行の reviewer 規範を書き換えて作る。
set -euo pipefail

cd "$(dirname "$0")/.."
check=scripts/check-reviewer-checklist.sh
src=skills/loop-engineering/reviewer.md
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0
names='見出し語とチェックリストの項目名が一致しない'
count='件数を数字で直書きしている'

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    pass) printf '合格   %s\n' "$2" ;;
    fail) printf '不合格 %s: exit %s(期待は %s)%s\n' "$2" "$3" "$4" "${5:+、stderr に「$5」が要る}" ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

expect() { # expect <exit> <stderr に含まれるべき文言(空なら不問)> <name> <file...>
  local want="$1" msg="$2" name="$3" got=0
  shift 3
  bash "$check" "$@" 2>"$tmp/err" || got=$?
  if [ "$got" -ne "$want" ] || { [ -n "$msg" ] && ! grep -q "$msg" "$tmp/err"; }; then
    msg fail "$name" "$got" "$want" "$msg"
    cat "$tmp/err"
    fail=1
  else
    msg pass "$name"
  fi
}
# 本文・チェックリストは現行のまま、末尾に 1 行足した fixture を作る
with_line() {
  {
    cat "$src"
    echo "$2"
  } >"$tmp/$1.md"
  echo "$tmp/$1.md"
}

for f in skills/*/reviewer.md; do expect 0 '' "repo $f" "$f"; done

sed 's/^- \*\*生成物の源泉一致\*\*/- **生成物の源泉が一致**/' "$src" >"$tmp/renamed.md"
expect 1 "$names" renamed-heading "$tmp/renamed.md"

sed '/^- 生成物の源泉一致 /d' "$src" >"$tmp/dropped.md"
expect 1 "$names" dropped-row "$tmp/dropped.md"

sed '/^- 生成物の源泉一致 /{h;d};/^- faithfulness-check /{p;x}' "$src" >"$tmp/reordered.md"
expect 1 "$names" reordered-row "$tmp/reordered.md"

expect 1 "$count" count-before-items "$(with_line cbi '15項目のチェックリストを埋める')"
expect 1 "$count" count-before-rows "$(with_line cbr '14行のチェックリスト')"
expect 1 "$count" count-after-items "$(with_line cai 'チェックリストは15項目')"
expect 1 "$count" count-after-rows "$(with_line car 'チェックリストに14行')"
expect 1 "$count" count-item-list "$(with_line cil '項目一覧は15項目')"
expect 1 "$count" count-before-item-list "$(with_line cbil '15項目の項目一覧')"
expect 0 '' count-one-ok "$(with_line c1 '1行のチェックリスト')"
expect 1 "$count" count-two-ng "$(with_line c2 '2行のチェックリスト')"
# 数字と対象語の間が 20 文字までなら検出、21 文字なら別の文脈とみなす
expect 1 "$count" gap-20 "$(with_line g20 "15項目あいうえおかきくけこさしすせそたちつてとチェックリスト")"
expect 0 '' gap-21 "$(with_line g21 "15項目あいうえおかきくけこさしすせそたちつてとなチェックリスト")"
expect 1 "$count" gap-20-after "$(with_line ga20 "チェックリストあいうえおかきくけこさしすせそたちつてと25項目")"
expect 0 '' gap-21-after "$(with_line ga21 "チェックリストあいうえおかきくけこさしすせそたちつてとな25項目")"

expect 1 "$names" mixed-files "$src" "$tmp/renamed.md"
# 1 件目の違反で止まらず、後続ファイルの違反も報告する
expect 1 "$tmp/dropped.md" all-violations-reported "$tmp/renamed.md" "$src" "$tmp/dropped.md"
# 引数なしはスクリプト位置基準で skills/*/reviewer.md を見る
mkdir -p "$tmp/repo/scripts" "$tmp/repo/skills/x"
cp "$check" "$tmp/repo/scripts/"
cp "$tmp/renamed.md" "$tmp/repo/skills/x/reviewer.md"
check="$tmp/repo/scripts/check-reviewer-checklist.sh" expect 1 'skills/x/reviewer.md' default-args
expect 1 'ファイルが無い' missing-file "$tmp/nope.md"

# 本文は出力フォーマットの手前まで、チェックリストは閉じ fence までしか数えない
expect 0 '' bold-after-body "$(with_line bab '- **余分**: x')"
expect 0 '' row-after-fence "$(with_line raf '- 余分 : x')"

# shellcheck disable=SC2016 # バッククォートは fence の文字そのもの(展開させない)
printf '## 必須ゲート\n1. **a**: x\n## 出力フォーマット\n```\n- 違反の雛形 : x\n```\n' >"$tmp/no-checklist.md"
expect 0 '' gate-without-checklist "$tmp/no-checklist.md"

sed '/^## 必須ゲート/d' "$src" >"$tmp/no-gate.md"
expect 1 '必須ゲート 節が無い' checklist-without-gate "$tmp/no-gate.md"

# `## チェックリスト` は出力フォーマット節の中のものだけを見る
printf '## 必須ゲート\n1. **a**: x\n## チェックリスト\n- a : x\n```\n## 出力フォーマット\n' >"$tmp/checklist-before-format.md"
expect 0 '' checklist-before-format "$tmp/checklist-before-format.md"
sed '/^## 出力フォーマット/i ## チェックリスト\n- 余分 : x\n```' "$src" >"$tmp/early-checklist.md"
expect 0 '' early-checklist-ignored "$tmp/early-checklist.md"

printf '# no gate section\n' >"$tmp/other-reviewer.md"
expect 0 '' other-format "$tmp/other-reviewer.md"

exit "$fail"
