#!/usr/bin/env bash
# session-start: skills/using-hymme/SKILL.md の本文(frontmatter 抜き)を additionalContext として注入する。
# Claude Code 専用(hookSpecificOutput 形式のみ)。SessionStart(matcher: startup|clear|compact)。stdin は使わない。
set -euo pipefail

root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
skill="${root}/skills/using-hymme/SKILL.md"

# 2 つ目の `---` 以降だけを出す(frontmatter を落とす)
body="$(awk 'f; /^---$/ { if (++c == 2) f = 1 }' "$skill")"
[ -n "$body" ] || { echo "session-start: ${skill} の本文が空か frontmatter が壊れている" >&2; exit 1; }

BODY="$body" python3 -I -c '
import json, os
ctx = ("<hymme-routing>\n"
       "hymme は superpowers 前提の拡張。以下は hymme:using-hymme スキルの全文(superpowers の工程のどこで hymme を呼ぶかの地図)。"
       "他の hymme / superpowers スキルは Skill ツールで呼ぶ。\n\n"
       + os.environ["BODY"] + "\n</hymme-routing>")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}, ensure_ascii=False))
'
