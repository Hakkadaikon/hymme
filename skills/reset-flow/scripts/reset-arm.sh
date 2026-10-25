#!/usr/bin/env bash
#
# reset-arm.sh — reset 実行直前の safety branch を作成し、git-guard hook の
# 解錠 marker（30 分有効）を置く。reset 本体は実行しない。
#
# Usage: reset-arm.sh [--allow-dirty]
#   --allow-dirty: 未コミット変更がある状態での arm を許可する。
#                  --hard で dirty を意図的に破棄する計画が承認済みの場合のみ。
set -euo pipefail

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    bad_opt) printf 'エラー: 不明なオプション: %s\n' "$2" ;;
    no_git) printf 'エラー: git リポジトリ内で実行すること\n' ;;
    detached) printf 'エラー: detached HEAD 状態では arm しない\n' ;;
    protected) printf 'エラー: 保護ブランチ (%s) では arm しない。reset は作業ブランチのみ\n' "$2" ;;
    remote_default) printf 'エラー: リモート既定ブランチ (%s) では arm しない\n' "$2" ;;
    dirty) printf 'エラー: 未コミット変更 %s ファイルあり。--hard なら完全消滅する。\n       破棄する計画が承認済みの場合のみ --allow-dirty を付けて再実行。\n' "$2" ;;
    armed) printf 'armed: %s(30 分有効 — git reset が git-guard hook を通過可能になる)\n' "$2" ;;
    dirty_note) printf '注意: 未コミット変更 %s ファイルは safety branch では守られない(--hard で消えたら復旧不能)\n' "$2" ;;
    recovery) printf 'reset を取り消す: reset-flow で target=%s として再度 reset(コミット分は完全復旧)\n' "$2" ;;
    keep) printf '注意: この safety branch はユーザーの明示承認があるまで削除しないこと\n' ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

allow_dirty=0
for a in "$@"; do
  case "$a" in
    --allow-dirty) allow_dirty=1 ;;
    *)
      msg bad_opt "$a" >&2
      exit 1
      ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || {
  msg no_git >&2
  exit 1
}

current=$(git rev-parse --abbrev-ref HEAD)
if [ "$current" = "HEAD" ]; then
  msg detached >&2
  exit 1
fi
# 保護ブランチでは arm しない（context の BLOCKER を素通りした直叩きを塞ぐ）
case "$current" in
  main | master | develop | development | trunk | release | release/* | releases/*)
    msg protected "$current" >&2
    exit 1
    ;;
esac
if def=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) &&
  [ "${def#refs/remotes/origin/}" = "$current" ]; then
  msg remote_default "$current" >&2
  exit 1
fi

dirty=$(git status --porcelain --untracked-files=no | wc -l)
if [ "$dirty" -gt 0 ] && [ "$allow_dirty" -ne 1 ]; then
  msg dirty "$dirty" >&2
  exit 1
fi

ts=$(date +%Y%m%d-%H%M%S)
name="backup/reset/${current}-${ts}"
n=1
while git show-ref --verify --quiet "refs/heads/$name"; do
  name="backup/reset/${current}-${ts}-${n}"
  n=$((n + 1))
done
git branch "$name" HEAD

marker=$(git rev-parse --git-path reset-flow.armed)
date +%s >"$marker"

echo "=== SAFETY ==="
echo "branch: $name"
echo "sha: $(git rev-parse HEAD)"
msg armed "$marker"
if [ "$dirty" -gt 0 ]; then
  msg dirty_note "$dirty"
fi
echo ""
echo "=== RECOVERY ==="
msg recovery "$name"
msg keep
