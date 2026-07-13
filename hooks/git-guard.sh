#!/usr/bin/env bash
# git-guard: 破壊的 git 操作のゲート。
# - git rebase / git pull --rebase: rebase-flow の arm marker(.git/rebase-flow.armed、30分有効)が無ければブロック。
#   git rebase --abort のみ常時許可(脱出経路)。
# - git reset: reset-flow の arm marker(.git/reset-flow.armed、30分有効)が無ければブロック。
# - git push: --force/-f(結合短フラグ含む)・値なし/sha なしの --force-with-lease・+refspec を常時ブロック。
#   検証済み tip を明示した --force-with-lease=<ref>:<sha> のみ許可。
# PreToolUse(matcher: Bash)。stdin に hook の JSON。ブロックは exit 2。
# ponytail: 既知の上限 — xargs 経由・シェル 3 段以上のネスト・`git -C <別リポ>` の marker 照合は
# cwd リポジトリ基準のまま。クォート内の実改行は行分割で別コマンド扱いになる(fail-closed の誤爆側)。
set -euo pipefail

payload="$(cat)"
PAYLOAD="$payload" python3 - <<'PY'
import json, os, re, shlex, subprocess, sys, time

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

# git の前に置かれても実行主体が変わらないラッパ。これらとそのオプション・数値引数は読み飛ばす
WRAPPERS = {"env", "command", "exec", "timeout", "nohup", "nice", "ionice", "stdbuf", "xargs", "sudo", "time"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}

def split_segments(text):
    # 行継続を潰してから行で切る(改行はセグメント境界)。; && || | & ( ) も境界
    text = text.replace("\\\n", " ")
    segments = []
    for line in text.split("\n"):
        try:
            lex = shlex.shlex(line, posix=True, punctuation_chars=";&|()")
            lex.whitespace_split = True
            tokens = list(lex)
        except ValueError:
            tokens = line.split()
        cur = []
        for t in tokens:
            if t and all(c in ";&|()" for c in t):
                if cur:
                    segments.append(cur)
                cur = []
            else:
                cur.append(t)
        if cur:
            segments.append(cur)
    return segments

def check_git(args):
    j = 0
    while j < len(args) and args[j].startswith("-"):
        j += 2 if args[j] in ("-C", "-c", "--git-dir", "--work-tree") else 1
    if j >= len(args):
        return
    sub, rest = args[j], args[j + 1:]

    if sub == "rebase" or (sub == "pull" and any(a in ("--rebase", "-r") or a.startswith("--rebase=") for a in rest)):
        if "--abort" in rest:
            return
        if not marker_fresh("rebase-flow.armed"):
            block("arm なしの git rebase は禁止。rebase-flow スキルの手順(計画提示 → 承認 → scripts/rebase-backup.sh)を通すこと。")
    elif sub == "reset":
        if not marker_fresh("reset-flow.armed"):
            block("arm なしの git reset は禁止。unstage なら git restore --staged。それ以外は reset-flow スキルの手順(計画提示 → 承認 → scripts/reset-arm.sh)を通すこと。")
    elif sub == "push":
        for a in rest:
            if a == "--force" or re.fullmatch(r"-[A-Za-z0-9]*f[A-Za-z0-9]*", a):
                block("生の force push は禁止。検証済み tip を指定した --force-with-lease=<branch>:<sha> のみ許可(rebase-flow §7)。")
            if a == "--force-with-lease" or (a.startswith("--force-with-lease=") and ":" not in a):
                block("期待 tip なしの --force-with-lease は弱い(remote-tracking 依存)。--force-with-lease=<branch>:<sha> の形で検証済み sha を明示すること。")
            if not a.startswith("-") and a.startswith("+"):
                block("+refspec による force push は禁止。--force-with-lease=<branch>:<sha> を使うこと。")

def scan(text, depth=0):
    for seg in split_segments(text):
        i = 0
        while i < len(seg):
            t = seg[i]
            base = os.path.basename(t)
            if ("=" in t and not t.startswith("-")) and base not in ("git",):
                i += 1  # env VAR=val
            elif base in WRAPPERS or t.startswith("-") or re.fullmatch(r"[\d.]+[smhd]?", t):
                i += 1  # ラッパ・そのオプション・timeout の秒数
            elif base in SHELLS:
                # sh -c "..." / bash -lc "..." の中身を再帰検査(2段まで)
                if depth < 2:
                    rest = seg[i + 1:]
                    for k, a in enumerate(rest):
                        if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", a) and k + 1 < len(rest):
                            scan(rest[k + 1], depth + 1)
                            break
                break
            elif base == "git":
                check_git(seg[i + 1:])
                break
            else:
                break  # 別コマンドのセグメント

scan(cmd)
PY
