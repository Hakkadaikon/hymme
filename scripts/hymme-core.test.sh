#!/usr/bin/env bash
# agentloop/lib/hymme(hook の入口、検査、記録、hymme コマンド)のテスト。要: python3, git。
# どの検査にも、通す例と止める例がある。
set -euo pipefail

cd "$(dirname "$0")/.."
python3 -m unittest discover -s agentloop/lib/tests
