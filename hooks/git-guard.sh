#!/usr/bin/env bash
# git-guard: 破壊的 git 操作のゲート。
# - git rebase / git pull --rebase: rebase-flow の arm marker(.git/rebase-flow.armed、30分有効)が無ければブロック。
#   git rebase --abort のみ常時許可(脱出経路)。
# - git reset: reset-flow の arm marker(.git/reset-flow.armed、30分有効)が無ければブロック。
# - git push --force / -f: 常時ブロック。明示 lease(--force-with-lease=<ref>:<sha>)のみ許可。
# PreToolUse(matcher: Bash)。stdin に hook の JSON。ブロックは exit 2。
set -euo pipefail

payload="$(cat)"
PAYLOAD="$payload" python3 - <<'PY'
import json, os, shlex, subprocess, sys, time

cmd = json.loads(os.environ.get("PAYLOAD", "{}")).get("tool_input", {}).get("command", "")

def marker_fresh(name):
    try:
        path = subprocess.run(
            ["git", "rev-parse", "--git-path", name],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        return time.time() - float(open(path).read().strip()) <= 1800
    except Exception:
        return False

def block(msg):
    print(f"git-guard: {msg}", file=sys.stderr)
    sys.exit(2)

try:
    tokens = shlex.split(cmd)
except ValueError:
    tokens = cmd.split()

# ; && || | ( で区切った各単純コマンドを検査する
segments, cur = [], []
for t in tokens:
    if t in (";", "&&", "||", "|", "&", "(", ")"):
        if cur:
            segments.append(cur)
        cur = []
    else:
        cur.append(t)
if cur:
    segments.append(cur)

for seg in segments:
    # env VAR=val プレフィックスと command/exec ラッパを飛ばす
    i = 0
    while i < len(seg) and ("=" in seg[i] and not seg[i].startswith("-") or seg[i] in ("env", "command", "exec")):
        i += 1
    if i >= len(seg) or os.path.basename(seg[i]) != "git":
        continue
    args = seg[i + 1:]
    # git のグローバルオプション(-C <path> / -c <kv> 等)を飛ばして subcommand を取る
    j = 0
    while j < len(args) and args[j].startswith("-"):
        j += 2 if args[j] in ("-C", "-c") else 1
    if j >= len(args):
        continue
    sub, rest = args[j], args[j + 1:]

    if sub == "rebase" or (sub == "pull" and any(a == "--rebase" or a.startswith("--rebase=") for a in rest)):
        if "--abort" in rest:
            continue
        if not marker_fresh("rebase-flow.armed"):
            block("arm なしの git rebase は禁止。rebase-flow スキルの手順(計画提示 → 承認 → scripts/rebase-backup.sh)を通すこと。")
    elif sub == "reset":
        if not marker_fresh("reset-flow.armed"):
            block("arm なしの git reset は禁止。unstage なら git restore --staged。それ以外は reset-flow スキルの手順(計画提示 → 承認 → scripts/reset-arm.sh)を通すこと。")
    elif sub == "push":
        for a in rest:
            if a in ("--force", "-f") or a == "--force-with-lease":
                block("生の force push は禁止。検証済み tip を指定した --force-with-lease=<branch>:<sha> のみ許可(rebase-flow §7)。")
PY
