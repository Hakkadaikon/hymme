#!/usr/bin/env bash
#
# rebase-verify.sh — rebase 実行後の機械検証。リポジトリは変更しない
# （rebase-backup.sh が置いた解錠 marker の除去のみ行う）。
#
# Usage: rebase-verify.sh <backup-ref> [base-ref]
#   backup-ref: rebase-backup.sh が作成した backup ブランチ
#   base-ref:   rebase-context.sh に渡したものと同じ base-ref。
#               渡すと onto 型でも比較範囲が正確になる（推奨）。
set -euo pipefail

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    usage) printf '使い方: rebase-verify.sh <backup-ref> [base-ref]\n' ;;
    bad_backup) printf "エラー: backup ref '%s' を解決できない\n" "$2" ;;
    in_progress) printf 'BLOCKER: rebase が完了していない(%s が存在)。--continue / --abort で終わらせてから検証する\n' "$2" ;;
    finished) printf 'rebase 完了状態(進行中の操作なし)\n' ;;
    bad_base) printf "WARNING: base-ref '%s' を解決できず、比較範囲が不正確になる可能性\n" "$2" ;;
    before) printf 'before (backup): %s 件\n' "$2" ;;
    after) printf 'after  (HEAD):   %s 件\n' "$2" ;;
    identical) printf 'identical: yes — 最終状態のファイル内容は rebase 前と完全一致\n(history-edit 型は yes が合格条件。drop を含む計画は除く)\n' ;;
    different) printf 'identical: no — 最終状態に差分あり\n(onto 型は base の新規コミット分が乗るため no が正常。history-edit 型で no の場合、差分が drop 意図分のみか要精査)\n' ;;
    h_range_diff) printf '=== RANGE DIFF（before/after のコミット対応） ===\n' ;;
    range_diff_legend) printf "読み方: '=' 同一 / '!' 内容差あり / '<' 消失(計画に無い drop なら異常) / '>' 新規\n" ;;
    range_diff_fail) printf '(range-diff 失敗)\n' ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

[ $# -ge 1 ] || {
  msg usage >&2
  exit 1
}
backup="$1"
base_ref="${2:-}"

git rev-parse --verify --quiet "${backup}^{commit}" >/dev/null ||
  {
    msg bad_backup "$backup" >&2
    exit 1
  }

echo "=== STATE ==="
for p in rebase-merge rebase-apply; do
  if [ -e "$(git rev-parse --git-path "$p")" ]; then
    msg in_progress "$p"
    exit 0
  fi
done
msg finished
# rebase は完了したので guard の解錠 marker を除去（再 rebase には再度 backup が必要）
rm -f "$(git rev-parse --git-path rebase-flow.armed)"
echo ""

mb=$(git merge-base "$backup" HEAD)
new_mb="$mb"
if [ -n "$base_ref" ]; then
  if base_sha=$(git rev-parse --verify --quiet "${base_ref}^{commit}"); then
    new_mb=$(git merge-base "$base_sha" HEAD)
  else
    msg bad_base "$base_ref"
  fi
fi

echo "=== COMMIT COUNT ==="
msg before "$(git rev-list --count "$mb".."$backup")"
msg after "$(git rev-list --count "$new_mb"..HEAD)"
echo ""

echo "=== TREE IDENTITY ==="
if git diff --quiet "$backup" HEAD; then
  msg identical
else
  msg different
  echo ""
  git diff --stat "$backup" HEAD | tail -30 || true
fi
echo ""

msg h_range_diff
msg range_diff_legend
if [ -n "$base_ref" ] && [ "$new_mb" != "$mb" ]; then
  git range-diff "$mb".."$backup" "$new_mb"..HEAD || msg range_diff_fail
else
  git range-diff "$backup"...HEAD || msg range_diff_fail
fi
echo ""

echo "=== NEW LOG ==="
git log --oneline --no-decorate "$new_mb"..HEAD
