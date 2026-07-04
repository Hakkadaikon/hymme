#!/usr/bin/env bash
# loop-engineering 0段ゲート: loop-outer/middle/inner を叩く前に
# tasks/loopeng/<Name>.extract.md の採番チェックリストが完成しているか検査する。
# 未完(台帳なし / [ ] 残り / S-NNN 欠番)なら exit 2 でブロックする。
# PreToolUse(matcher: Bash)。stdin に hook の JSON。
set -euo pipefail

payload="$(cat)"
cmd="$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"

# 先頭の env VAR=val プレフィックスを飛ばし、実行されるコマンド名(語頭)を取る。
# echo/grep の引数に loop-* が出るだけの誤爆を避けるため、部分一致でなく語頭一致で判定する。
verb="$(printf '%s' "$cmd" | awk '{for(i=1;i<=NF;i++){if($i!~/=/){print $i;exit}}}')"
case "$verb" in
  loop-outer|loop-middle|loop-inner) ;;
  *) exit 0 ;;
esac

# SPEC=<Name> を抜く。無ければ判定不能なので素通り(別の検証に委ねる)
name="$(printf '%s' "$cmd" | grep -oE 'SPEC=[A-Za-z0-9_]+' | head -n1 | cut -d= -f2 || true)"
[ -n "$name" ] || exit 0

ledger="tasks/loopeng/${name}.extract.md"

block() { echo "loopeng 0段ゲート: $1" >&2; exit 2; }

[ -f "$ledger" ] || block "抽出台帳 $ledger が無い。assets/extract-template.md をコピーして埋めてから loop-* を回せ。"

# 「## 台帳」以降だけを対象にする(テンプレ見出しの例 [ ] を拾わないため)
body="$(awk '/^## 台帳/{f=1;next} /^## /{if(f)exit} f' "$ledger")"

# 未チェック行が残っていればブロック
if printf '%s' "$body" | grep -qE '^\s*- \[ \] S-'; then
  block "$ledger に未チェック(- [ ] S-...)が残っている。全 ID を EARS へ変換して [x] にしてから進め。"
fi

# S-NNN の連番に欠番が無いか確認
ids="$(printf '%s' "$body" | grep -oE 'S-[0-9]+' | sort -u || true)"
[ -n "$ids" ] || block "$ledger に S-NNN の ID が1つも無い。台帳が空。"

nums="$(printf '%s' "$ids" | sed 's/^S-0*//' | sort -n)"
first="$(printf '%s' "$nums" | head -n1)"
last="$(printf '%s' "$nums" | tail -n1)"
count="$(printf '%s\n' "$nums" | grep -c .)"
expected=$(( last - first + 1 ))
if [ "$count" -ne "$expected" ]; then
  block "$ledger の ID 連番に欠番がある(S-$first..S-$last のうち $count 件)。抜けを埋めるか採番し直せ。"
fi

exit 0
