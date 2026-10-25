#!/usr/bin/env bash
#
# pr-context.sh — 作業ブランチの「ベースブランチ（分岐元）」を特定し、
# PR 作成に必要なコミット差分情報をまとめて出力する。read-only。
#
# ベースブランチは「リモートリポジトリの既定ブランチ」ではなく、
# 現在の作業ブランチが分岐した元ブランチをローカルで探索して決める。
#
# Usage:
#   pr-context.sh [base-branch]
#     base-branch を渡すと探索せずそれをベースとして使う。
#
# 出力は `=== SECTION ===` 区切りのプレーンテキスト。呼び出し側（スキル）が
# これを読んでタイトル・本文を組み立てる。
set -euo pipefail

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    no_git) printf 'エラー: git リポジトリ内で実行すること\n' ;;
    detached) printf 'エラー: detached HEAD 状態。ブランチをチェックアウトすること\n' ;;
    no_remote) printf 'remote: (なし)\n' ;;
    repo_unknown) printf 'repo: (不明)\n' ;;
    no_root) printf '(repo root 不明 — 検出不可)\n' ;;
    no_template) printf '(テンプレートなし — 汎用構成で本文を組む)\n' ;;
    primary) printf 'primary: %s  ← これを使う(独自フォーマット禁止)\n' "$2" ;;
    multi) printf 'multi (複数テンプレ。候補提示してユーザーに選んでもらう):\n' ;;
    no_ci) printf '(CI workflow なし)\n' ;;
    no_cli) printf 'cli: (該当 CLI なし。手動作成へフォールバック)\n' ;;
    no_base) printf '(特定できなかった。ユーザーに確認すること)\n' ;;
    no_base_note) printf 'main / master / develop / origin/HEAD いずれとも分岐関係を特定できなかった。\nベースブランチを引数で明示して再実行すること: pr-context.sh <base-branch>\n' ;;
    base_explicit) printf '(引数で明示指定)\n' ;;
    base_detected) printf '(分岐元として自動検出)\n' ;;
    unpushed) printf 'WARNING: ローカルに未 push のコミットが %s 件ある。push はユーザーが実施すること\n' "$2" ;;
    no_upstream) printf 'upstream: (未設定 — リモート未 push)\nWARNING: このブランチはリモートに push されていない。PR 作成前にユーザーが push する必要がある\n' ;;
    full_diff) printf '完全な差分が必要な場合: git diff %s...HEAD\n' "$2" ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

base_override="${1:-}"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  msg no_git >&2
  exit 1
fi

current=$(git rev-parse --abbrev-ref HEAD)
if [ "$current" = "HEAD" ]; then
  msg detached >&2
  exit 1
fi

# --- ベースブランチ探索 ---------------------------------------------------
# 候補ブランチそれぞれと HEAD の merge-base を取り、HEAD から merge-base まで
# のコミット数（= 分岐後の距離）が最小の候補を「直近の分岐元」とみなす。
# 距離が小さいほど近い枝分かれ。距離 0（差分なし）の候補は後回し。
detect_base() {
  if [ -n "$base_override" ]; then
    echo "$base_override"
    return
  fi

  local -a candidates=()
  # origin の既定ブランチ（origin/HEAD）があれば候補に加える
  local def
  if def=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
    candidates+=("${def#refs/remotes/}")
  fi
  # よくあるベースブランチ名（ローカル / origin 両方）
  local b
  for b in main master develop development trunk; do
    git show-ref --verify --quiet "refs/heads/$b" && candidates+=("$b") || true
    git show-ref --verify --quiet "refs/remotes/origin/$b" && candidates+=("origin/$b") || true
  done

  local head_sha
  head_sha=$(git rev-parse HEAD)

  local c mb dist
  local best="" best_dist=-1 # 距離 > 0 の最小
  local zero_best=""         # 距離 0 のフォールバック候補
  for c in "${candidates[@]}"; do
    # 現在のブランチ自身は除外（origin/<current> も）
    [ "$c" = "$current" ] && continue
    [ "$c" = "origin/$current" ] && continue
    mb=$(git merge-base "$c" HEAD 2>/dev/null) || continue
    if [ "$mb" = "$head_sha" ]; then
      # 候補が HEAD の子孫または同一。分岐元ではない
      continue
    fi
    dist=$(git rev-list --count "$mb"..HEAD)
    if [ "$dist" -eq 0 ]; then
      [ -z "$zero_best" ] && zero_best="$c"
      continue
    fi
    if [ "$best_dist" -lt 0 ] || [ "$dist" -lt "$best_dist" ]; then
      best_dist="$dist"
      best="$c"
    fi
  done

  if [ -n "$best" ]; then
    echo "$best"
  elif [ -n "$zero_best" ]; then
    echo "$zero_best"
  else
    echo "" # 特定できず
  fi
}

# --- リポジトリ同定 -------------------------------------------------------
# 「今どのリポジトリ・どの作業ディレクトリに対して PR を作ろうとしているか」を
# 明示する。呼び出し側は、これと PR を作る対象が一致することを確認し、
# 会話に混ざった別リポジトリの内容を本文へ混入させないための錨にする。
detect_repo_identity() {
  local url host slug root
  root=$(git rev-parse --show-toplevel 2>/dev/null || echo "?")
  echo "worktree-root: $root"
  url=$(git remote get-url origin 2>/dev/null || git remote get-url "$(git remote | head -1)" 2>/dev/null || echo "")
  if [ -z "$url" ]; then
    msg no_remote
    msg repo_unknown
    return
  fi
  host=$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]+@##; s#[:/].*$##')
  # slug = host より後ろの owner/repo（末尾 .git を除去）
  slug=$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]+@##; s#^[^:/]+[:/]##; s#\.git$##')
  echo "remote: $url"
  echo "host: $host"
  echo "repo: $slug"
}

# --- テンプレート検出 -----------------------------------------------------
# PR/MR テンプレートをリポジトリルートから決定論的に探す。モデルが手で find を
# 打つと打ち忘れ・スキップが起きるため、ここで確定させる。単一テンプレ（探索順
# で最初の 1 つを primary）と複数テンプレ（ディレクトリ形式。候補提示が必要）を
# 区別して出す。
detect_templates() {
  local root c f
  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    msg no_root
    return
  }

  local -a singles=()
  local -a multi=()

  # GitHub 単一テンプレ候補（探索順。大小両表記を確認）
  local -a gh_candidates=(
    ".github/pull_request_template.md"
    ".github/PULL_REQUEST_TEMPLATE.md"
    "pull_request_template.md"
    "PULL_REQUEST_TEMPLATE.md"
    "docs/pull_request_template.md"
    "docs/PULL_REQUEST_TEMPLATE.md"
  )
  for c in "${gh_candidates[@]}"; do
    [ -f "$root/$c" ] && singles+=("$c")
  done

  # GitHub 複数テンプレ（.github/PULL_REQUEST_TEMPLATE/*.md）
  if [ -d "$root/.github/PULL_REQUEST_TEMPLATE" ]; then
    while IFS= read -r f; do [ -n "$f" ] && multi+=("$f"); done \
      < <(cd "$root" && find .github/PULL_REQUEST_TEMPLATE -maxdepth 1 -iname '*.md' 2>/dev/null | sort)
  fi

  # GitLab MR テンプレ（.gitlab/merge_request_templates/*.md）
  if [ -d "$root/.gitlab/merge_request_templates" ]; then
    while IFS= read -r f; do [ -n "$f" ] && multi+=("$f"); done \
      < <(cd "$root" && find .gitlab/merge_request_templates -maxdepth 1 -iname '*.md' 2>/dev/null | sort)
  fi

  if [ ${#singles[@]} -eq 0 ] && [ ${#multi[@]} -eq 0 ]; then
    msg no_template
    return
  fi
  if [ ${#singles[@]} -gt 0 ]; then
    msg primary "$root/${singles[0]}"
    local i
    for ((i = 1; i < ${#singles[@]}; i++)); do
      echo "other:   $root/${singles[$i]}"
    done
  fi
  if [ ${#multi[@]} -gt 0 ]; then
    msg multi
    for c in "${multi[@]}"; do
      echo "  - $root/$c"
    done
  fi
}

# --- CI workflow 検出 -----------------------------------------------------
# ローカルで回した検証ゲートは CI 全 workflow の部分集合でしかない。差分の
# ファイル種別とここに出た workflow のトリガーを突き合わせ、ローカル未実行の
# ジョブ(fmt/lint/docs 等)が無いか呼び出し側が確認するための素材を出す。
detect_workflows() {
  local root f
  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    msg no_root
    return
  }
  local found=0
  if [ -d "$root/.github/workflows" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && {
        echo "workflow: $f"
        found=1
      }
    done < <(cd "$root" && find .github/workflows -maxdepth 1 \( -iname '*.yml' -o -iname '*.yaml' \) 2>/dev/null | sort)
  fi
  [ -f "$root/.gitlab-ci.yml" ] && {
    echo "workflow: .gitlab-ci.yml"
    found=1
  }
  if [ "$found" -eq 0 ]; then
    msg no_ci
    return
  fi
  echo "changed-file extensions: $(git diff "$1"...HEAD --name-only 2>/dev/null | sed -n 's/.*\.\([A-Za-z0-9_]\{1,10\}\)$/\1/p' | sort -u | tr '\n' ' ')"
}

# --- プラットフォーム判定 -------------------------------------------------
# remote URL のホストから github / gitlab / bitbucket を判定し、使用 CLI と
# その有無を出す。ホスト不明（GHE 等の self-hosted 含む）は unknown とし、
# CLI の有無を頼りに呼び出し側が判断する。
detect_platform() {
  local url host platform cli cli_found
  url=$(git remote get-url origin 2>/dev/null || git remote get-url "$(git remote | head -1)" 2>/dev/null || echo "")
  if [ -z "$url" ]; then
    msg no_remote
    echo "platform: none"
    return
  fi
  # scheme:// と user@ を除去し、最初の : か / までをホストとして取る
  host=$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]+@##; s#[:/].*$##')

  case "$host" in
    github.com | *.github.com)
      platform=github
      cli=gh
      ;;
    gitlab.com | *.gitlab.com)
      platform=gitlab
      cli=glab
      ;;
    bitbucket.org)
      platform=bitbucket
      cli=""
      ;;
    *github*)
      platform=github
      cli=gh
      ;; # GHE 等
    *gitlab*)
      platform=gitlab
      cli=glab
      ;; # self-hosted GitLab
    *)
      platform=unknown
      cli=""
      ;;
  esac

  echo "remote: $url"
  echo "host: $host"
  echo "platform: $platform"
  if [ -n "$cli" ]; then
    if command -v "$cli" >/dev/null 2>&1; then cli_found=yes; else cli_found=no; fi
    echo "cli: $cli (installed: $cli_found)"
  else
    msg no_cli
  fi
}

base=$(detect_base)

echo "=== CURRENT BRANCH ==="
echo "$current"
echo ""

echo "=== REPO IDENTITY ==="
detect_repo_identity
echo ""

echo "=== PLATFORM ==="
detect_platform
echo ""

echo "=== TEMPLATE ==="
detect_templates
echo ""

echo "=== BASE BRANCH ==="
if [ -z "$base" ]; then
  msg no_base
  echo ""
  echo "=== NOTE ==="
  msg no_base_note
  exit 0
fi
echo "$base"
if [ -n "$base_override" ]; then
  msg base_explicit
else
  msg base_detected
fi
echo ""

mb=$(git merge-base "$base" HEAD)

echo "=== UPSTREAM / PUSH STATUS ==="
# 現ブランチの追跡先と ahead/behind。スキルは push 状態の判断に使う（push は代行しない）
if upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
  echo "upstream: $upstream"
  counts=$(git rev-list --left-right --count "$upstream"...HEAD 2>/dev/null || echo "? ?")
  behind=$(echo "$counts" | awk '{print $1}')
  ahead=$(echo "$counts" | awk '{print $2}')
  echo "ahead: $ahead / behind: $behind"
  if [ "$ahead" != "0" ]; then
    msg unpushed "$ahead"
  fi
else
  msg no_upstream
fi
echo ""

echo "=== COMMITS ($base..HEAD) ==="
git log "$base"..HEAD --oneline --no-decorate || true
echo ""

echo "=== COMMIT MESSAGES (full) ==="
# 本文素材。subject + body をコミットごとに出す
git log "$base"..HEAD --format='--- %h %s%n%b' || true
echo ""

echo "=== DIFF STAT ($base...HEAD) ==="
git diff "$base"...HEAD --stat || true
echo ""

echo "=== CHANGED FILES ==="
git diff "$base"...HEAD --name-status || true
echo ""

echo "=== CI WORKFLOWS ==="
detect_workflows "$base"
echo ""

echo "=== NOTE ==="
msg full_diff "$base"
echo "merge-base: $mb"
