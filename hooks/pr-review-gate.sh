#!/usr/bin/env bash
# pr-review-gate: gh pr create の前に diff-review の証跡を検査するゲート。
# リポジトリルートの tasks/diff-review/evidence.md が「commit: 現 HEAD」かつ「must: 0」
# でなければブロックする。git リポジトリ外・HEAD 取得不能・証跡の形式不正は fail-closed。
# PreToolUse(matcher: Bash)。stdin に hook の JSON。ブロックは exit 2。
set -euo pipefail

payload="$(cat)"
PAYLOAD="$payload" python3 - <<'PY'
import json, os, re, subprocess, sys

cmd = json.loads(os.environ.get("PAYLOAD", "{}")).get("tool_input", {}).get("command", "")

def block(msg):
    print(f"pr-review-gate: {msg}", file=sys.stderr)
    sys.exit(2)

def verify():
    try:
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        block("git リポジトリの状態を確認できない(fail-closed)。リポジトリ内で HEAD が取れる状態にしてから gh pr create を実行しろ。")
    try:
        text = open(os.path.join(root, "tasks/diff-review/evidence.md")).read()
    except OSError:
        block("PR 作成前に diff-review スキルを must 指摘ゼロまで実施しろ(証跡: tasks/diff-review/evidence.md)。")
    m_commit = re.search(r"^commit:\s*(\S+)", text, re.M)
    m_must = re.search(r"^must:\s*(\d+)\s*$", text, re.M)
    if not m_commit or not m_must:
        block("証跡 tasks/diff-review/evidence.md の commit:/must: が読めない(fail-closed)。diff-review を再実行して証跡を書き直せ。")
    if m_commit.group(1) != head:
        block("証跡が古い(レビュー後にコミットが進んだ)。diff-review を再実行しろ。")
    if int(m_must.group(1)) != 0:
        block("must 指摘が残っている。修正して再レビューしろ。")

if re.search(r"\bgh\b.*\bpr\s+create\b", cmd):
    verify()
PY
