#!/usr/bin/env bash
# hymme 自身のスクリプトの品質ゲート: Python は ruff(静的解析とフォーマット)、シェルは shellcheck と shfmt。
# 使い方: lint.sh [--fix]   (--fix はフォーマットと自動修正を書き戻す)
# 要: ruff, shellcheck, shfmt が PATH にあること(nix develop か flake の checks が用意する)。
set -euo pipefail

cd "$(dirname "$0")/.."
fix=0
[ "${1:-}" = --fix ] && fix=1

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    start) printf '== %s ==\n' "$2" ;;
    ok) printf '品質ゲート: すべて通った\n' ;;
    ng) printf '品質ゲート: 通らなかった検査がある(%s)。scripts/lint.sh --fix で直せるものは直る\n' "$2" ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

mapfile -t py < <(find hooks loopeng scripts skills -name '*.py' -type f | sort)
mapfile -t sh < <(find hooks loopeng scripts skills -name '*.sh' -type f | sort)
failed=()

if [ "$fix" -eq 1 ]; then
  ruff check --fix "${py[@]}" || true
  ruff format "${py[@]}"
  shfmt -w "${sh[@]}"
fi

msg start "ruff check"
ruff check "${py[@]}" || failed+=("ruff check")
msg start "ruff format --check"
ruff format --check "${py[@]}" || failed+=("ruff format")
msg start "shellcheck"
shellcheck -x "${sh[@]}" || failed+=("shellcheck")
msg start "shfmt -d"
shfmt -d "${sh[@]}" || failed+=("shfmt")

if [ "${#failed[@]}" -eq 0 ]; then
  msg ok
else
  msg ng "${failed[*]}"
  exit 1
fi
