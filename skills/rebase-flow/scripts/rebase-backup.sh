#!/usr/bin/env bash
#
# rebase-backup.sh — rebase 実行直前のバックアップブランチを作成し、
# 復旧コマンドを出力する。rebase 本体は実行しない。
#
# Usage: rebase-backup.sh
set -euo pipefail

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    no_git) printf 'エラー: git リポジトリ内で実行すること\n' ;;
    detached) printf 'エラー: detached HEAD 状態では backup を作成しない\n' ;;
    protected) printf 'エラー: 保護ブランチ (%s) では backup/arm しない。rebase は作業ブランチのみ\n' "$2" ;;
    remote_default) printf 'エラー: リモート既定ブランチ (%s) では backup/arm しない\n' "$2" ;;
    dirty) printf 'エラー: working tree が clean ではない。backup 作成を中止(rebase-context.sh の BLOCKER を先に解消すること)\n' ;;
    armed) printf 'armed: %s(30 分有効 — git rebase が git-guard hook を通過可能になる)\n' "$2" ;;
    upstream_tip) printf 'upstream-tip: %s (%s — force-push 時の lease 候補)\n' "$2" "$3" ;;
    recovery) printf 'rebase 進行中に中断する : git rebase --abort\nrebase 完了後に全て戻す : git reset --hard %s   # ユーザー実行(要 clean tree)\n検証                    : bash <skill-dir>/scripts/rebase-verify.sh %s <base-ref>\n' "$2" "$2" ;;
    keep) printf '注意: この backup ブランチはユーザーの明示承認があるまで削除しないこと\n' ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

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
if ! git diff --quiet || ! git diff --cached --quiet; then
  msg dirty >&2
  exit 1
fi

ts=$(date +%Y%m%d-%H%M%S)
name="backup/rebase/${current}-${ts}"
n=1
while git show-ref --verify --quiet "refs/heads/$name"; do
  name="backup/rebase/${current}-${ts}-${n}"
  n=$((n + 1))
done
git branch "$name" HEAD

# git-guard hook を解錠する marker（30 分有効）。
# これが「backup なしで git rebase を実行できない」ことの機械的担保になる。
marker=$(git rev-parse --git-path rebase-flow.armed)
date +%s >"$marker"

echo "=== BACKUP ==="
echo "branch: $name"
echo "sha: $(git rev-parse HEAD)"
msg armed "$marker"
if upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
  msg upstream_tip "$(git rev-parse "$upstream")" "$upstream"
fi
echo ""
echo "=== RECOVERY ==="
msg recovery "$name"
echo ""
msg keep
