#!/usr/bin/env bash
# diff-review: レビュー対象差分の決定論的収集(読み取り専用・stdout のみ)
#
# 使い方:
#   collect-diff.sh manifest [<base-ref>]                    範囲解決 + コミット一覧 + 統計(小径なら全文同梱)
#   collect-diff.sh commit <sha>                             単一コミットの diff(除外適用)
#   collect-diff.sh worktree                                 未コミット変更の diff(staged + unstaged)
#   collect-diff.sh cumulative [<base-ref>] [-- <path>...]   累積 diff(path 明示時は除外を適用しない)
set -euo pipefail

INLINE_THRESHOLD=300 # 累積 diff(除外分を除く)がこの行数以下なら manifest に全文を同梱

# lockfile・生成物: 全文は出力せず統計のみ(git pathspec、'*' はディレクトリ区切りもまたぐ)
EXCLUDE_PATTERNS=(
  '*.lock'
  '*.lockfile'
  '*package-lock.json'
  '*pnpm-lock.yaml'
  '*go.sum'
  '*.min.js'
  '*.min.css'
)
EXCLUDE_PATHSPEC=()
for p in "${EXCLUDE_PATTERNS[@]}"; do
  EXCLUDE_PATHSPEC+=(":(exclude)$p")
done

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    usage) sed -n '2,8p' "$0" | cut -c3- ;;
    no_base) printf 'エラー: デフォルトブランチを特定できない。base-ref を引数で指定すること\n' ;;
    no_sha) printf 'エラー: commit <sha> の形式で指定すること\n' ;;
    none) printf '(なし)\n' ;;
    h_commits) printf '== COMMITS (base..HEAD, 古い順) ==\n' ;;
    h_worktree) printf '== WORKTREE (未コミット変更: staged + unstaged) ==\n' ;;
    h_untracked) printf '== UNTRACKED (未追跡ファイル: Read ツールで参照する) ==\n' ;;
    h_untracked_wt) printf '== UNTRACKED (Read ツールで参照する) ==\n' ;;
    untracked_file) printf '  %s (%s 行)\n' "$2" "$3" ;;
    h_excluded) printf '== EXCLUDED (lockfile・生成物: 統計のみ、全文は取得不可) ==\n' ;;
    size) printf 'total_changed_lines=%s (除外分を除く) + untracked_lines=%s\n' "$2" "$3" ;;
    h_full) printf '== FULL DIFF (total <= %s のため同梱。未追跡ファイルは含まない) ==\n' "$2" ;;
    h_full_skip) printf '== FULL DIFF 省略 (total > %s) ==\n' "$2" ;;
    full_skip_hint) printf 'commit <sha> / worktree / cumulative [-- <path>...] で必要な単位のみ取得すること\n' ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

# BASE_REF / BASE_SHA を解決する。引数 > origin/HEAD > main / master の順
resolve_base() {
  local base_ref="${1:-}"
  if [[ -z "$base_ref" ]]; then
    base_ref=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  fi
  if [[ -z "$base_ref" ]]; then
    local c
    for c in main master; do
      if git rev-parse --quiet --verify "refs/heads/$c" >/dev/null; then
        base_ref="$c"
        break
      fi
    done
  fi
  if [[ -z "$base_ref" ]]; then
    msg no_base >&2
    exit 1
  fi
  BASE_REF="$base_ref"
  BASE_SHA=$(git merge-base "$base_ref" HEAD)
}

# numstat をインデント付き "path +adds -dels" に整形する
format_numstat() {
  awk -F'\t' '{printf "  %s +%s -%s\n", $3, $1, $2}'
}

line_count() { # line_count <path>: 通常ファイルの行数。ディレクトリ(未追跡のシンボリックリンク先など)は 0
  if [[ -f "$1" ]]; then wc -l <"$1" | tr -d ' '; else echo 0; fi
}

# numstat の総変更行数(バイナリ "-" は除く)
sum_numstat() {
  awk -F'\t' '{ if ($1 != "-") t += $1; if ($2 != "-") t += $2 } END { print t + 0 }'
}

cmd_manifest() {
  resolve_base "${1:-}"
  local head_sha branch commits untracked
  head_sha=$(git rev-parse HEAD)
  branch=$(git symbolic-ref --quiet --short HEAD || echo "(detached)")
  commits=$(git log --reverse --format='%h %s' "$BASE_SHA..HEAD")
  untracked=$(git ls-files --others --exclude-standard)

  if [[ -z "$commits" && -z "$untracked" ]] && git diff --quiet HEAD; then
    echo "NO_CHANGES"
    return
  fi

  echo "== RANGE =="
  echo "base_ref=$BASE_REF"
  echo "base=$BASE_SHA"
  echo "head=$head_sha (branch: $branch)"
  echo

  msg h_commits
  if [[ -z "$commits" ]]; then
    msg none
  else
    local sha subject
    while read -r sha _; do
      subject=$(git log -1 --format='%s' "$sha")
      echo "- $sha $subject"
      git show --numstat --format= "$sha" -- . "${EXCLUDE_PATHSPEC[@]}" | format_numstat | sed 's/^/  /'
    done <<<"$commits"
  fi
  echo

  msg h_worktree
  local worktree_stat
  worktree_stat=$(git diff --numstat HEAD -- . "${EXCLUDE_PATHSPEC[@]}")
  if [[ -z "$worktree_stat" ]]; then
    msg none
  else
    format_numstat <<<"$worktree_stat"
  fi
  echo

  msg h_untracked
  if [[ -z "$untracked" ]]; then
    msg none
  else
    local f
    while IFS= read -r f; do
      msg untracked_file "$f" "$(line_count "$f")"
    done <<<"$untracked"
  fi
  echo

  msg h_excluded
  local excluded_stat
  excluded_stat=$(git diff --numstat "$BASE_SHA" -- "${EXCLUDE_PATTERNS[@]}")
  if [[ -z "$excluded_stat" ]]; then
    msg none
  else
    format_numstat <<<"$excluded_stat"
  fi
  echo

  local total untracked_lines=0
  total=$(git diff --numstat "$BASE_SHA" -- . "${EXCLUDE_PATHSPEC[@]}" | sum_numstat)
  if [[ -n "$untracked" ]]; then
    local f
    while IFS= read -r f; do
      untracked_lines=$((untracked_lines + $(line_count "$f")))
    done <<<"$untracked"
  fi
  echo "== SIZE =="
  msg size "$total" "$untracked_lines"
  echo

  if ((total <= INLINE_THRESHOLD)); then
    msg h_full "$INLINE_THRESHOLD"
    git diff "$BASE_SHA" -- . "${EXCLUDE_PATHSPEC[@]}"
  else
    msg h_full_skip "$INLINE_THRESHOLD"
    msg full_skip_hint
  fi
}

cmd_commit() {
  local sha="${1:-}"
  if [[ -z "$sha" ]]; then
    msg no_sha >&2
    exit 1
  fi
  git show "$sha" -- . "${EXCLUDE_PATHSPEC[@]}"
}

cmd_worktree() {
  git diff HEAD -- . "${EXCLUDE_PATHSPEC[@]}"
  local untracked
  untracked=$(git ls-files --others --exclude-standard)
  if [[ -n "$untracked" ]]; then
    echo
    msg h_untracked_wt
    local f
    while IFS= read -r f; do
      echo "  $f"
    done <<<"$untracked"
  fi
}

cmd_cumulative() {
  local base_arg="" paths=()
  while (($#)); do
    case "$1" in
      --)
        shift
        paths=("$@")
        break
        ;;
      *)
        base_arg="$1"
        shift
        ;;
    esac
  done
  resolve_base "$base_arg"
  if ((${#paths[@]})); then
    git diff "$BASE_SHA" -- "${paths[@]}"
  else
    git diff "$BASE_SHA" -- . "${EXCLUDE_PATHSPEC[@]}"
  fi
}

sub="${1:-}"
if (($#)); then shift; fi
case "$sub" in
  manifest) cmd_manifest "$@" ;;
  commit) cmd_commit "$@" ;;
  worktree) cmd_worktree ;;
  cumulative) cmd_cumulative "$@" ;;
  *)
    msg usage >&2
    exit 1
    ;;
esac
