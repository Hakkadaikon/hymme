#!/usr/bin/env python3
"""pr-review-gate.sh の判定本体: PR 作成の前に diff-review の証跡を検査し、満たさなければ exit 2 で止める。"""

import json
import os
import re
import subprocess
import sys

cmd = json.loads(os.environ.get("PAYLOAD", "{}")).get("tool_input", {}).get("command", "")

MESSAGES = {
    "no_repo": "git リポジトリの状態を確認できない(fail-closed)。"
    "リポジトリ内で HEAD が取れる状態にしてから PR を作る。",
    "no_evidence": "PR 作成前に diff-review スキルを must 指摘ゼロまで実施する(証跡: tasks/diff-review/evidence.md)。",
    "bad_evidence": "証跡 tasks/diff-review/evidence.md の commit:/must: が読めない(fail-closed)。"
    "diff-review を再実行して証跡を書き直す。",
    "stale": "証跡が古い(レビュー後にコミットが進んだ)。diff-review を再実行する。",
    "must_left": "must 指摘が残っている。修正して再レビューする。",
}


def msg(code, **kw):
    """端末に出す文言をコードから引く(文言をこの表1か所に集める)。"""
    return "pr-review-gate: " + MESSAGES.get(code, "未知のメッセージコード: " + code).format(**kw)


def block(code):
    print(msg(code), file=sys.stderr)
    sys.exit(2)


def verify():
    try:
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except Exception:
        block("no_repo")
    try:
        text = open(os.path.join(root, "tasks/diff-review/evidence.md")).read()
    except OSError:
        block("no_evidence")
    m_commit = re.search(r"^commit:\s*(\S+)", text, re.M)
    m_must = re.search(r"^must:\s*(\d+)\s*$", text, re.M)
    if not m_commit or not m_must:
        block("bad_evidence")
    if m_commit.group(1) != head:
        block("stale")
    if int(m_must.group(1)) != 0:
        block("must_left")


if re.search(r"\bgh\b.*\bpr\s+create\b", cmd):
    verify()
