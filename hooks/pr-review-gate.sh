#!/usr/bin/env bash
# pr-review-gate: gh pr create の前に diff-review の証跡を検査するゲート。
# リポジトリルートの tasks/diff-review/evidence.md が「commit: 現 HEAD」かつ「must: 0」
# でなければブロックする。git リポジトリ外・HEAD 取得不能・証跡の形式不正は fail-closed。
# PreToolUse(matcher: Bash)。stdin に hook の JSON。ブロックは exit 2。
set -euo pipefail

# 途中で cd しても切り出した .py を見失わないよう、hook の置き場所を先に絶対パスにする
here="$(cd "$(dirname "$0")" && pwd)"

payload="$(cat)"
PAYLOAD="$payload" python3 -I "$here/pr_review_gate.py"
