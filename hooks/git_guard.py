#!/usr/bin/env python3
"""git-guard.sh の判定本体。

PAYLOAD 環境変数の hook JSON から git コマンドを読み、許可しない操作なら exit 2 で止める。
"""

import json
import os
import re
import shlex
import subprocess
import sys
import time

cmd = json.loads(os.environ.get("PAYLOAD", "{}")).get("tool_input", {}).get("command", "")


def marker_fresh(name):
    try:
        path = subprocess.run(
            ["git", "rev-parse", "--git-path", name],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        return time.time() - float(open(path).read().strip()) <= 1800
    except Exception:
        return False


MESSAGES = {
    "rebase": "arm なしの git rebase は禁止。rebase-flow スキルの手順"
    "(計画提示 → 承認 → scripts/rebase-backup.sh)を通す。",
    "reset": "arm なしの git reset は禁止。unstage なら git restore --staged を使う。"
    "それ以外は reset-flow スキルの手順(計画提示 → 承認 → scripts/reset-arm.sh)を通す。",
    "force": "生の force push は禁止。検証済み tip を指定した --force-with-lease=<branch>:<sha> だけ許可する"
    "(rebase-flow §7)。",
    "lease": "期待 tip なしの --force-with-lease は弱い(remote-tracking 依存)。"
    "--force-with-lease=<branch>:<sha> の形で検証済み sha を明示する。",
    "refspec": "+refspec による force push は禁止。--force-with-lease=<branch>:<sha> を使う。",
    "semicolon": "`;` で直前コマンドと連結された git commit は禁止(直前の失敗を無視して走る)。"
    "`&&` か if で失敗時に止まる形にする。",
    "tail_head": "`| tail`/`| head` を経た行での git commit は禁止(パイプの exit がフィルタ側になり、"
    "検証の赤が握り潰される)。検証は `grep -q` など exit に判定が乗る形にするか、コミットを別コマンドに分ける。",
}


def msg(code, **kw):
    """端末に出す文言をコードから引く(文言をこの表1か所に集める)。"""
    return "git-guard: " + MESSAGES.get(code, "未知のメッセージコード: " + code).format(**kw)


def block(code):
    print(msg(code), file=sys.stderr)
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
    sub, rest = args[j], args[j + 1 :]

    if sub == "rebase" or (sub == "pull" and any(a in ("--rebase", "-r") or a.startswith("--rebase=") for a in rest)):
        if "--abort" in rest:
            return
        if not marker_fresh("rebase-flow.armed"):
            block("rebase")
    elif sub == "reset":
        if not marker_fresh("reset-flow.armed"):
            block("reset")
    elif sub == "push":
        for a in rest:
            if a == "--force" or re.fullmatch(r"-[A-Za-z0-9]*f[A-Za-z0-9]*", a):
                block("force")
            if a == "--force-with-lease" or (a.startswith("--force-with-lease=") and ":" not in a):
                block("lease")
            if not a.startswith("-") and a.startswith("+"):
                block("refspec")


def line_parts(line):
    # split_segments と同じ字句化だが、直前の連結子(; && || | 等)を保持する
    try:
        lex = shlex.shlex(line, posix=True, punctuation_chars=";&|()")
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        tokens = line.split()
    parts, cur, conn = [], [], None
    for t in tokens:
        if t and all(c in ";&|()" for c in t):
            if cur:
                parts.append((conn, cur))
                cur = []
            conn = t
        else:
            cur.append(t)
    if cur:
        parts.append((conn, cur))
    return parts


def git_sub(seg):
    i = 0
    while i < len(seg):
        t = seg[i]
        base = os.path.basename(t)
        if ("=" in t and not t.startswith("-")) and base != "git":
            i += 1
        elif base in WRAPPERS or t.startswith("-") or re.fullmatch(r"[\d.]+[smhd]?", t):
            i += 1
        elif base == "git":
            args = seg[i + 1 :]
            j = 0
            while j < len(args) and args[j].startswith("-"):
                j += 2 if args[j] in ("-C", "-c", "--git-dir", "--work-tree") else 1
            return args[j] if j < len(args) else None
        else:
            return None
    return None


def check_commit_chain(text):
    # ゲート素通しコミットの2パターンを同一行内で検出する。
    # if 文の then 節(`if 検証; then git commit; fi`)はセグメント先頭が then になるので誤爆しない。
    for line in text.replace("\\\n", " ").split("\n"):
        parts = line_parts(line)
        for idx, (conn, seg) in enumerate(parts):
            if git_sub(seg) != "commit":
                continue
            if conn == ";":
                block("semicolon")
            for pconn, pseg in parts[:idx]:
                if pconn == "|" and pseg and os.path.basename(pseg[0]) in ("tail", "head"):
                    block("tail_head")


def scan(text, depth=0):
    check_commit_chain(text)
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
                    rest = seg[i + 1 :]
                    for k, a in enumerate(rest):
                        if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", a) and k + 1 < len(rest):
                            scan(rest[k + 1], depth + 1)
                            break
                break
            elif base == "git":
                check_git(seg[i + 1 :])
                break
            else:
                break  # 別コマンドのセグメント


scan(cmd)
