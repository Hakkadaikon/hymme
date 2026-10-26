#!/usr/bin/env bash
# session-start.sh の回帰テスト。出力が JSON として読め、注入文に未展開の ${CLAUDE_PLUGIN_ROOT} が残らないこと。
# & を含むプラグインのパスでも壊れないこと(bash の置換は版で & の扱いが違う)。
set -euo pipefail

src="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
root="$tmp/a&b"
mkdir -p "$root"
cp -R "$src/hooks" "$src/skills" "$root/"
find "$root" -exec chmod u+w {} +

out="$(CLAUDE_PLUGIN_ROOT="$root" bash "$root/hooks/session-start.sh")"
# shellcheck disable=SC2016 # python のコードと、検査したい変数名そのものの文字列
if ROOT="$root" python3 -I -c '
import json, os, sys
ctx = json.loads(sys.stdin.read())["hookSpecificOutput"]["additionalContext"]
sys.exit(0 if "${CLAUDE_PLUGIN_ROOT}" not in ctx and os.environ["ROOT"] + "/skills/" in ctx else 1)
' <<<"$out"; then
  printf '合格   session-start-expands-root\n'
else
  printf '不合格 session-start-expands-root\n%s\n' "$out"
  exit 1
fi
