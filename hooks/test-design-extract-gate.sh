#!/usr/bin/env bash
# test-design 0段ゲート: テストファイルへの Write/Edit の前に、
# tasks/test-design/<対象>.md の T-ID 台帳が完成しているか検査する。
# 台帳が無いプロジェクト/タスクは素通り(誤爆ゼロを優先)。
# 台帳が1つでもあれば、未チェック(- [ ] T-...)や T-NNN 欠番が残っていないか検査し、
# 残っていれば exit 2 でブロックする。
# PreToolUse(matcher: Write|Edit)。stdin に hook の JSON。
set -euo pipefail

payload="$(cat)"
file_path="$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null || true)"
[ -n "$file_path" ] || exit 0

# テストファイルでなければ対象外(実装ファイル・ドキュメント編集まで縛らない)
case "$file_path" in
  *.test.*|*.spec.*|*test_*|*_test.*) ;;
  *) exit 0 ;;
esac

ledger_dir="tasks/test-design"
[ -d "$ledger_dir" ] || exit 0

# 台帳が1つも無ければ対象外(このリポジトリ/タスクでは台帳運用をしていない)
ledgers="$(find "$ledger_dir" -maxdepth 1 -name '*.md' 2>/dev/null || true)"
[ -n "$ledgers" ] || exit 0

block() { echo "test-design 0段ゲート: $1" >&2; exit 2; }

for ledger in $ledgers; do
  # 「## 台帳」以降だけを対象にする(テンプレ見出しの例を拾わないため)
  body="$(awk '/^## 台帳/{f=1;next} /^## /{if(f)exit} f' "$ledger")"
  [ -n "$body" ] || continue

  if printf '%s' "$body" | grep -qE '^\s*- \[ \] T-'; then
    block "$ledger に未チェック(- [ ] T-...)が残っている。手法割り当てとテスト名を埋めて [x] にしてから実装へ進め。"
  fi

  ids="$(printf '%s' "$body" | grep -oE 'T-[0-9]+' | sort -u || true)"
  [ -n "$ids" ] && {
    nums="$(printf '%s' "$ids" | sed 's/^T-0*//' | sort -n)"
    first="$(printf '%s' "$nums" | head -n1)"
    last="$(printf '%s' "$nums" | tail -n1)"
    count="$(printf '%s\n' "$nums" | grep -c .)"
    expected=$(( last - first + 1 ))
    if [ "$count" -ne "$expected" ]; then
      block "$ledger の T-ID 連番に欠番がある(T-$first..T-$last のうち $count 件)。抜けを埋めるか採番し直せ。"
    fi
  }
done

exit 0
