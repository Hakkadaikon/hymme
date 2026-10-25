#!/usr/bin/env bash
# loop-engineering 静的検査ゲート: `tlc` / `java ... tlc2.TLC` を直接叩く前に、
# 対象 spec を loopeng/bin/tla_lint.sh(SANY + 型注釈があれば Apalache typecheck)に通す。
# spec にエラーがあれば(lint の exit 1)exit 2 でブロックし、エラー内容を返す(直してから TLC を回させる)。
# ツール不在など spec の誤りでない失敗(lint の exit 2)はブロックせず、警告だけ出して通す。
# `make ... loop-middle` 等は Makefile 側の lint ターゲットが同じ検査をするので対象外。
# PreToolUse(matcher: Bash)。stdin に hook の JSON。
#
# ponytail: コマンド文字列を shlex で区切って `cd <dir>` と tlc の引数だけ追う。
# サブシェル・変数展開・スクリプト内からの tlc 呼び出しは見えない(oracle は自前で判定する)。
# 1 行に複数の tlc があるときは最後の spec だけを検査する。
set -euo pipefail

payload="$(cat)"
spec="$(printf '%s' "$payload" | python3 -I -c '
import json, os, shlex, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cmd = data.get("tool_input", {}).get("command", "")
cwd = data.get("cwd") or os.getcwd()
try:
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    toks = list(lex)
except ValueError:
    sys.exit(0)
seg = []
def flush(seg, cwd):
    words = list(seg)
    while words and "=" in words[0] and not words[0].startswith("-"):  # 先頭の VAR=val を除く
        words.pop(0)
    if not words:
        return cwd, None
    if words[0] == "cd" and len(words) > 1:
        return os.path.join(cwd, os.path.expanduser(words[1])), None
    if os.path.basename(words[0]) == "tlc":
        args = words[1:]
    elif "tlc2.TLC" in words:
        args = words[words.index("tlc2.TLC") + 1:]
    else:
        return cwd, None
    # TLC は最後の非オプション引数を spec(拡張子は省略可)として取る
    cand = [a for a in args if a.endswith(".tla")] or ([args[-1]] if args and not args[-1].startswith("-") else [])
    if not cand:
        return cwd, None
    path = os.path.join(cwd, cand[-1])
    if not path.endswith(".tla"):
        path += ".tla"
    return cwd, path
found = None
for t in toks + [";"]:
    if t and set(t) <= set(";&|()"):
        cwd, p = flush(seg, cwd)
        found = p or found
        seg = []
    else:
        seg.append(t)
if found:
    print(found)
' 2>/dev/null || true)"

[ -n "$spec" ] && [ -f "$spec" ] || exit 0

lint="$(dirname "$0")/../loopeng/bin/tla_lint.sh"
rc=0
out="$(bash "$lint" "$spec" 2>&1)" || rc=$?
case "$rc" in
  0) exit 0 ;;
  1)
    echo "loopeng 静的検査ゲート: $spec が静的検査を通らない。直してから TLC を回せ。" >&2
    printf '%s\n' "$out" >&2
    exit 2
    ;;
  *)
    echo "loopeng 静的検査ゲート: 静的検査を実行できなかった(spec の誤りではない)。TLC はそのまま通す。" >&2
    printf '%s\n' "$out" >&2
    exit 0
    ;;
esac
