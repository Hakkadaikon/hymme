#!/usr/bin/env bash
# git-guard: 破壊的 git 操作のゲート。
# - git rebase / git pull --rebase: rebase-flow の arm marker(.git/rebase-flow.armed、30分有効)が無ければブロック。
#   git rebase --abort のみ常時許可(脱出経路)。
# - git reset: reset-flow の arm marker(.git/reset-flow.armed、30分有効)が無ければブロック。
# - git push: --force/-f(結合短フラグ含む)・値なし/sha なしの --force-with-lease・+refspec を常時ブロック。
#   検証済み tip を明示した --force-with-lease=<ref>:<sha> のみ許可。
# - git commit: 同一行で (a) `;` の直前連結、(b) 先行セグメントに `| tail`/`| head` があるとブロック。
#   どちらも「検証ゲートの赤が exit に反映されないままコミットが走る」再発事例のパターン。
#   `検証 && git commit` と `検証 | grep -q ... && git commit`(exit が判定を反映する形)は許可。
# PreToolUse(matcher: Bash)。stdin に hook の JSON。ブロックは exit 2。
# ponytail: 既知の上限 — xargs 経由・シェル 3 段以上のネスト・`git -C <別リポ>` の marker 照合は
# cwd リポジトリ基準のまま。クォート内の実改行は行分割で別コマンド扱いになる(fail-closed の誤爆側)。
set -euo pipefail

# 途中で cd しても切り出した .py を見失わないよう、hook の置き場所を先に絶対パスにする
# (シンボリックリンク経由の呼び出しは実体へ辿り、CDPATH の出力は捨てる)
self="$(realpath "$0" 2>/dev/null || python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0")"
here="$(CDPATH='' cd -P "$(dirname "$self")" >/dev/null && pwd -P)"

payload="$(cat)"
PAYLOAD="$payload" python3 -I "$here/git_guard.py"
