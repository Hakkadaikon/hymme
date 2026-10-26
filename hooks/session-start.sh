#!/usr/bin/env bash
# session-start: skills/using-hymme/SKILL.md の本文(frontmatter 抜き)を additionalContext として注入する。
# Claude Code 専用(hookSpecificOutput 形式のみ)。SessionStart(matcher: startup|clear|compact)。stdin は使わない。
set -euo pipefail

root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
skill="${root}/skills/using-hymme/SKILL.md"

# 2 つ目の `---` 以降だけを出す(frontmatter を落とす)
body="$(awk 'f; /^---$/ { if (++c == 2) f = 1 }' "$skill")"
msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    empty_body) printf 'session-start: %s の本文が空か frontmatter が壊れている\n' "$2" ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

[ -n "$body" ] || {
  msg empty_body "$skill" >&2
  exit 1
}

# 注入文は変数を展開しないので、Read させるパスを実パスに置き換える(bash の置換は版で & やクォートの扱いが違うので python で)
# shellcheck disable=SC2016 # python のコードと、置換したい変数名そのものの文字列
BODY="$body" ROOT="$root" python3 -I -c '
import json, os
ctx = ("<hymme-routing>\n"
       "hymme は superpowers 前提の拡張。以下は using-hymme(skills/using-hymme/SKILL.md)の全文(superpowers の工程のどこで hymme を呼ぶかの地図)。"
       "他の hymme / superpowers スキルは Skill ツールで呼ぶ。一覧に出さないスキル(loopeng-*、test-extract / test-catalog / test-verify、tdd-cycle、flakiness-* など)は、ルーターや下の地図の指示で SKILL.md を Read して使う。\n\n"
       + os.environ["BODY"].replace("${CLAUDE_PLUGIN_ROOT}", os.environ["ROOT"]) + "\n</hymme-routing>")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}, ensure_ascii=False))
'
