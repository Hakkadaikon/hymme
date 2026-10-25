#!/usr/bin/env bash
#
# reset-context.sh — git reset 計画に必要な情報とガードレール判定材料を
# まとめて出力する。read-only。
#
# Usage:
#   reset-context.sh <target-ref> <hard|mixed|soft>
#     target-ref: reset 先（例: backup/rebase/..., HEAD~1, origin/main, SHA）
#     mode:       実行予定の reset モード（失われるものの判定に使う）
#
# 出力は `=== SECTION ===` 区切り。
#   BLOCKER: が 1 行でもあれば reset 計画に進んではならない。
#   WARNING: は全て計画に明記して承認対象に含める。
set -euo pipefail

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    usage) printf '使い方: reset-context.sh <target-ref> <hard|mixed|soft>\n' ;;
    bad_mode) printf 'エラー: mode は hard | mixed | soft のいずれか(指定: %s)\n' "$2" ;;
    no_git) printf 'エラー: git リポジトリ内で実行すること\n' ;;
    bad_target) printf "エラー: target-ref '%s' を解決できない\n" "$2" ;;
    verdict_blocker) printf '判定: BLOCKER あり — reset 計画に進まないこと\n' ;;
    verdict_warning) printf '判定: WARNING あり — 全て計画に明記し、承認対象に含めること\n' ;;
    verdict_ok) printf '判定: ガードレール上の支障なし — 計画提示へ\n' ;;
    none) printf '(なし)\n' ;;
    detached) printf 'detached HEAD 状態。ブランチをチェックアウトしてから実行する\n' ;;
    reason_static) printf '静的リスト\n' ;;
    reason_origin) printf 'origin/HEAD(リモート既定ブランチ)\n' ;;
    reason_github) printf 'GitHub 既定ブランチ\n' ;;
    protected) printf '保護ブランチ (%s — %s) 上での reset は禁止。作業ブランチでのみ実行可\n' "$2" "$3" ;;
    in_progress) printf '進行中の操作あり: %s(reset で潰さず、--abort / --continue で終わらせること)\n' "$2" ;;
    rel_same) printf 'relationship: HEAD と同一\n' ;;
    same_noop) printf 'HEAD と同一への --%s reset は何もしない(指定誤りの可能性)\n' "$2" ;;
    rel_ancestor) printf 'relationship: HEAD の祖先(コミットを巻き戻す)\n' ;;
    rel_descendant) printf 'relationship: HEAD の子孫(前進 — 巻き戻しではない)\n' ;;
    rel_divergent) printf 'relationship: 分岐(共通祖先: %s)\n' "$2" ;;
    divergent) printf 'target は HEAD と分岐している。現在の枝のコミットを離れて別の枝へ乗り換える reset になる\n' ;;
    h_leaving) printf '=== COMMITS LEAVING BRANCH（ブランチから外れるコミット） ===\n' ;;
    leaving_note) printf '注意: これらは branch から到達不能になる(reflog と safety branch には残る)\n' ;;
    pushed) printf '外れるコミットのうち %s 件は push 済み。reset 後はリモートと分岐し、リモート反映には force-push が必要(rebase-flow §7 と同じ手順)\n' "$2" ;;
    no_leaving) printf '(なし — コミットは失われない)\n' ;;
    dirty_hard) printf -- '--hard は未コミット変更 %s ファイルを完全に消す。コミットにも reflog にも残らず復旧不能。破棄が意図なら計画にファイル一覧を明記し、arm 時に --allow-dirty を付ける\n' "$2" ;;
    dirty_keep) printf '未コミット変更 %s ファイルあり(--%s では保持される。mixed は unstage される)\n' "$2" "$3" ;;
    untracked) printf 'untracked: %s 件(reset では消えない)\n' "$2" ;;
    stash) printf 'stash: %s 件\n' "$2" ;;
    no_upstream) printf 'upstream: (未設定)\n' ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

if [ $# -lt 2 ]; then
  msg usage >&2
  exit 1
fi
target_ref="$1"
mode="$2"
case "$mode" in
  hard | mixed | soft) ;;
  *)
    msg bad_mode "$mode" >&2
    exit 1
    ;;
esac

blockers=0
warnings=0
blocker() { # blocker <code> [args...]
  echo "BLOCKER: $(msg "$@")"
  blockers=$((blockers + 1))
}
warning() { # warning <code> [args...]
  echo "WARNING: $(msg "$@")"
  warnings=$((warnings + 1))
}

print_summary() {
  echo "=== SUMMARY ==="
  echo "blockers: $blockers / warnings: $warnings"
  if [ "$blockers" -gt 0 ]; then
    msg verdict_blocker
  elif [ "$warnings" -gt 0 ]; then
    msg verdict_warning
  else
    msg verdict_ok
  fi
}

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  msg no_git >&2
  exit 1
fi

echo "=== CURRENT BRANCH ==="
current=$(git rev-parse --abbrev-ref HEAD)
if [ "$current" = "HEAD" ]; then
  blocker detached
  echo ""
  print_summary
  exit 0
fi
echo "branch: $current"
echo "head: $(git rev-parse HEAD)"
# 保護ブランチ判定: 静的リスト + リモート既定ブランチ（origin/HEAD → gh fallback）。
# rebase / reset / force-push が許されるのは作業ブランチのみ。
protected_reason() {
  local b="$1" def
  case "$b" in
    main | master | develop | development | trunk | release | release/* | releases/*)
      msg reason_static
      return 0
      ;;
  esac
  if def=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
    if [ "${def#refs/remotes/origin/}" = "$b" ]; then
      msg reason_origin
      return 0
    fi
  elif command -v gh >/dev/null 2>&1; then
    def=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)
    if [ -n "$def" ] && [ "$def" = "$b" ]; then
      msg reason_github
      return 0
    fi
  fi
  return 1
}
if preason=$(protected_reason "$current"); then
  blocker protected "$current" "$preason"
fi
echo ""

echo "=== IN-PROGRESS OPERATIONS ==="
op_found=no
for p in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
  if [ -e "$(git rev-parse --git-path "$p")" ]; then
    blocker in_progress "$p"
    op_found=yes
  fi
done
[ "$op_found" = no ] && msg none
echo ""

echo "=== TARGET ==="
if ! target_sha=$(git rev-parse --verify --quiet "${target_ref}^{commit}"); then
  msg bad_target "$target_ref" >&2
  exit 1
fi
head_sha=$(git rev-parse HEAD)
echo "target-ref: $target_ref ($target_sha)"
echo "mode: --$mode"
if [ "$target_sha" = "$head_sha" ]; then
  rel="same"
elif git merge-base --is-ancestor "$target_sha" HEAD; then
  rel="ancestor"
elif git merge-base --is-ancestor HEAD "$target_sha"; then
  rel="descendant"
else
  rel="divergent"
fi
case "$rel" in
  same)
    msg rel_same
    [ "$mode" != "hard" ] && blocker same_noop "$mode"
    ;;
  ancestor) msg rel_ancestor ;;
  descendant) msg rel_descendant ;;
  divergent)
    msg rel_divergent "$(git merge-base "$target_sha" HEAD)"
    warning divergent
    ;;
esac
echo ""

msg h_leaving
leaving=$(git rev-list --count "$target_sha"..HEAD)
echo "count: $leaving"
if [ "$leaving" -gt 0 ]; then
  git log --oneline --no-decorate "$target_sha"..HEAD | head -50 || true
  echo ""
  msg leaving_note
  if upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
    pushed=$((leaving - $(git rev-list --count "$target_sha"..HEAD --not "$upstream")))
    if [ "$pushed" -gt 0 ]; then
      warning pushed "$pushed"
    fi
  fi
else
  msg no_leaving
fi
echo ""

echo "=== WORKING TREE ==="
dirty=$(git status --porcelain --untracked-files=no | wc -l)
if [ "$dirty" -gt 0 ]; then
  if [ "$mode" = "hard" ]; then
    warning dirty_hard "$dirty"
    git status --short --untracked-files=no | head -20 || true
  else
    msg dirty_keep "$dirty" "$mode"
  fi
else
  echo "clean"
fi
msg untracked "$(git ls-files --others --exclude-standard | wc -l)"
msg stash "$(git stash list | wc -l)"
echo ""

echo "=== UPSTREAM ==="
if upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
  echo "upstream: $upstream ($(git rev-parse "$upstream"))"
else
  msg no_upstream
fi
echo ""

print_summary
