#!/usr/bin/env bash
# gh-ci-investigate.sh — GitHub Actions の失敗調査を gh 経由で決定論的に収集する。
#
# WebFetch は github.com の Actions ログを取れない（HTML が返るだけでログにならない）。
# 失敗ジョブ・ステップと「失敗ステップのログだけ」は gh で確実に
# 取れるので、URL / run_id / PR 番号を渡された時点でこのスクリプトに解決させる。
#
# 使い方:
#   gh-ci-investigate.sh parse     <url|run_id|#PR|pr:PR>            解決結果(host/repo/run/job/pr)のみ出力
#   gh-ci-investigate.sh preflight  [url|run_id|#PR|pr:PR]          失敗ジョブ/ステップ/結論の要約（空=cwd repo の最新 run）
#   gh-ci-investigate.sh logs       [url|run_id|#PR|pr:PR] [--job <id>]   失敗ステップのログのみ
#
# 受理する入力:
#   https://HOST/OWNER/REPO/actions/runs/RUNID[/job/JOBID][/attempts/N][?pr=NN]
#   https://HOST/OWNER/REPO/pull/PRNUM[/checks]
#   RUNID          … 全桁数字。repo は cwd の remote から gh が解決
#   #PRNUM / pr:PRNUM … repo は cwd から解決
#   (空)           … cwd repo の最新 run
#
# 修正は一切行わない。収集だけ。GitHub(github.com / GitHub Enterprise)専用。
set -euo pipefail

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    error) printf 'エラー: %s\n' "$2" ;;
    bad_url_owner) printf 'URL から OWNER/REPO を取れない: %s\n' "$2" ;;
    bad_url_kind) printf 'URL から actions run / pull を特定できない: %s\n' "$2" ;;
    bad_input) printf '入力を解釈できない: %s(URL / run_id / #PR / 空 のいずれか)\n' "$2" ;;
    bad_opt) printf '不明なオプション: %s\n' "$2" ;;
    no_gh) printf 'gh が見つからない。GitHub CLI を導入すること\n' ;;
    no_repo) printf 'URL も run_id も無く、git リポジトリ外。URL か run_id を指定すること\n' ;;
    no_latest) printf '最新の run を特定できない。URL か run_id を指定すること\n' ;;
    parse_needs_input) printf 'parse には入力が必要\n' ;;
    pr_no_fail_run) printf 'PR #%s に失敗 run が見つからない。preflight で確認すること\n' "$2" ;;
    bad_sub) printf '未知のサブコマンド: %s(parse | preflight | logs)\n' "$2" ;;
    cwd_remote) printf '(cwd の remote)\n' ;;
    none) printf '(なし)\n' ;;
    run_header) printf -- '--- run %s: 結論と失敗ジョブ/ステップ ---\n' "$2" ;;
    run_meta_fail) printf '  (run %s のメタ取得に失敗。権限/hostname/認証を確認)\n' "$2" ;;
    failed_jobs) printf '  失敗ジョブ・ステップ:\n' ;;
    jobs_fail) printf '  (ジョブ内訳を取得できなかった)\n' ;;
    pr_checks) printf 'PR #%s の checks:\n' "$2" ;;
    pr_checks_fail) printf '  (pr checks 取得失敗)\n' ;;
    failed_runs) printf '失敗 check の run:\n' ;;
    no_failed_run_id) printf '  失敗している check の run_id を特定できなかった\n' ;;
    next_logs) printf '失敗ステップのログ取得:\n' ;;
    logs_note) printf '注意: PR #%s の失敗 run のうち先頭 (%s) のログを表示する。複数あるときは preflight の一覧から run_id を直接指定すること\n' "$2" "$3" ;;
    log_pending) printf '(ログ未確定。run がまだ実行中か、権限不足の可能性。要約に戻る)\n' ;;
    log_fail) printf '(失敗ログを取得できなかった。run がまだ実行中か、権限不足の可能性。要約に戻る)\n' ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

die() { # die <code> [args...]
  msg error "$(msg "$@")" >&2
  exit 1
}

HOST=""
REPO=""
RUN_ID=""
JOB_ID=""
PR=""

# 入力を HOST/REPO/RUN_ID/JOB_ID/PR に正規化する。URL からは HOST と REPO も取れるが、
# 数字・#PR・空のときは REPO を空のままにして gh に cwd の remote を解決させる。
parse_input() {
  local in="${1:-}"
  [ -n "$in" ] || return 0
  case "$in" in
    http*://*)
      local rest path owner repo
      rest="${in#*://}"
      HOST="${rest%%/*}"
      path="${rest#*/}"
      path="${path%%\?*}" # ?pr= 等のクエリは落とす（run から辿れる）
      owner="${path%%/*}"
      path="${path#*/}"
      repo="${path%%/*}"
      path="${path#*/}"
      [ -n "$owner" ] && [ -n "$repo" ] || die bad_url_owner "$in"
      REPO="$owner/$repo"
      case "/$path/" in
        */actions/runs/*)
          local after="${path#*actions/runs/}"
          RUN_ID="${after%%/*}"
          case "$path" in
            */job/*)
              JOB_ID="${path#*/job/}"
              JOB_ID="${JOB_ID%%/*}"
              ;;
          esac
          ;;
        */pull/*)
          PR="${path#*pull/}"
          PR="${PR%%/*}"
          ;;
        *) die bad_url_kind "$in" ;;
      esac
      ;;
    \#[0-9]*) PR="${in#\#}" ;;
    pr:[0-9]*) PR="${in#pr:}" ;;
    [0-9]*) RUN_ID="$in" ;;
    *) die bad_input "$in" ;;
  esac
}

cmd="${1:-preflight}"
shift || true
input=""
for a in "$@"; do
  case "$a" in
    --job) NEXT_IS_JOB=1 ;;
    -*) die bad_opt "$a" ;;
    *)
      if [ "${NEXT_IS_JOB:-0}" = 1 ]; then
        JOB_ID="$a"
        NEXT_IS_JOB=0
      else input="$a"; fi
      ;;
  esac
done

command -v gh >/dev/null 2>&1 || die no_gh
parse_input "$input"

# -R フラグ: URL 由来で REPO が取れたときだけ明示。無ければ gh が cwd の remote を使う。
RARGS=()
[ -n "$REPO" ] && RARGS=(-R "$HOST/$REPO")

# cwd 依存の解決には git リポジトリが要る。
need_cwd_repo() {
  [ -n "$REPO" ] && return 0
  git rev-parse --git-dir >/dev/null 2>&1 ||
    die no_repo
}

# PR → 失敗している check の run_id 群（重複排除）。bucket=="fail" が失敗系をまとめる。
pr_failed_run_ids() {
  gh pr checks "$PR" "${RARGS[@]}" --json bucket,link \
    --jq '.[] | select(.bucket=="fail") | .link' 2>/dev/null |
    grep -oE 'runs/[0-9]+' | grep -oE '[0-9]+' | sort -u
}

# 空入力 → cwd repo の最新 run。
resolve_latest_run() {
  RUN_ID="$(gh run list -L 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  [ -n "$RUN_ID" ] || die no_latest
}

run_summary() { # $1 = run_id
  msg run_header "$1"
  gh run view "$1" "${RARGS[@]}" \
    --json displayTitle,status,conclusion,headBranch,event,workflowName,url \
    --jq '"title:     \(.displayTitle)\nworkflow:  \(.workflowName)\nbranch:    \(.headBranch)  event: \(.event)\nstatus:    \(.status)  conclusion: \(.conclusion)\nurl:       \(.url)"' ||
    {
      msg run_meta_fail "$1"
      return 0
    }
  msg failed_jobs
  gh run view "$1" "${RARGS[@]}" --json jobs \
    --jq '.jobs[] | select(.conclusion=="failure" or .conclusion=="cancelled" or .conclusion=="timed_out")
            | "  ✗ job: \(.name) [\(.conclusion)] (id: \(.databaseId))",
              (.steps[] | select(.conclusion=="failure" or .conclusion=="cancelled" or .conclusion=="timed_out")
               | "      step \(.number): \(.name) [\(.conclusion)]")' ||
    msg jobs_fail
}

case "$cmd" in
  parse)
    [ -n "$input" ] || die parse_needs_input
    echo "=== RESOLVED ==="
    echo "host:    ${HOST:-$(msg cwd_remote)}"
    echo "repo:    ${REPO:-$(msg cwd_remote)}"
    echo "run_id:  ${RUN_ID:-$(msg none)}"
    echo "job_id:  ${JOB_ID:-$(msg none)}"
    echo "pr:      ${PR:-$(msg none)}"
    ;;

  preflight)
    need_cwd_repo
    echo "=== TARGET ==="
    echo "host:   ${HOST:-$(msg cwd_remote)}"
    echo "repo:   ${REPO:-$(msg cwd_remote)}"
    echo
    echo "=== AUTH ==="
    if [ -n "$HOST" ]; then
      gh auth status --hostname "$HOST" 2>&1 | sed 's/^/  /' || true
    else gh auth status 2>&1 | sed 's/^/  /' || true; fi
    echo
    echo "=== FAILED CI ==="
    if [ -n "$PR" ]; then
      msg pr_checks "$PR"
      gh pr checks "$PR" "${RARGS[@]}" 2>&1 | sed 's/^/  /' || msg pr_checks_fail
      echo
      local_ids="$(pr_failed_run_ids || true)"
      if [ -n "$local_ids" ]; then
        msg failed_runs
        while read -r rid; do [ -n "$rid" ] && run_summary "$rid"; done <<<"$local_ids"
      else
        msg no_failed_run_id
      fi
    else
      [ -n "$RUN_ID" ] || resolve_latest_run
      run_summary "$RUN_ID"
    fi
    echo
    echo "=== NEXT ==="
    msg next_logs
    if [ -n "$JOB_ID" ]; then
      echo "  bash <skill-dir>/scripts/gh-ci-investigate.sh logs '${input:-$RUN_ID}' --job $JOB_ID"
    else
      echo "  bash <skill-dir>/scripts/gh-ci-investigate.sh logs '${input:-$RUN_ID}'"
    fi
    ;;

  logs)
    need_cwd_repo
    if [ -n "$PR" ] && [ -z "$RUN_ID" ]; then
      RUN_ID="$(pr_failed_run_ids | head -n1 || true)"
      [ -n "$RUN_ID" ] || die pr_no_fail_run "$PR"
      msg logs_note "$PR" "$RUN_ID"
      echo
    fi
    [ -n "$RUN_ID" ] || resolve_latest_run
    echo "=== FAILED LOG (run $RUN_ID${JOB_ID:+, job $JOB_ID}) ==="
    # --log-failed は失敗ステップのログだけを返す（full log ではないので context に優しい）。
    # run が実行中だとログ未確定でエラーになるため、その場合は要約にフォールバックする。
    if [ -n "$JOB_ID" ]; then
      gh run view "$RUN_ID" --job "$JOB_ID" --log-failed "${RARGS[@]}" 2>/dev/null ||
        gh run view "$RUN_ID" --job "$JOB_ID" --log "${RARGS[@]}" 2>/dev/null ||
        {
          msg log_pending
          run_summary "$RUN_ID"
        }
    else
      gh run view "$RUN_ID" --log-failed "${RARGS[@]}" 2>/dev/null ||
        {
          msg log_fail
          run_summary "$RUN_ID"
        }
    fi
    ;;

  *)
    die bad_sub "$cmd"
    ;;
esac
