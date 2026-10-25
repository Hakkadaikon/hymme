#!/usr/bin/env bash
# test-design 0段ゲート: テストファイルへの Write/Edit の前に、
# tasks/test-design/<対象>.md の T-ID 台帳が完成しているか検査する。
# 台帳が無いプロジェクト/タスクは素通り(誤爆ゼロを優先)。
# 台帳が1つでもあれば、未チェック(- [ ] T-...)や T-NNN 欠番が残っていないか検査し、
# 残っていれば exit 2 でブロックする。
# 加えて tasks/loopeng/ に .feature があるのに台帳へ1件も転記されていなければブロックする
# (loopeng-gherkin の成果物が test-design 側で握りつぶされるのを防ぐ)。
# 台帳は、書こうとしているファイルが属する git リポジトリの tasks/ から探す(無ければ cwd)。
# 台帳に「テスト対象: <glob> ...」の行があれば、その台帳は一致するテストファイルにだけ効く。
# この行が無い台帳は、すべてのテストファイルに効く。
# PreToolUse(matcher: Write|Edit)。stdin に hook の JSON。
set -euo pipefail

# 途中で cd しても切り出した .py を見失わないよう、hook の置き場所を先に絶対パスにする
here="$(cd "$(dirname "$0")" && pwd)"

payload="$(cat)"
file_path="$(printf '%s' "$payload" | python3 -I -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null || true)"
[ -n "$file_path" ] || exit 0

# テストファイルでなければ対象外(実装ファイル・ドキュメント編集まで縛らない)
case "$file_path" in
  *.test.* | *.spec.* | *test_* | *_test.*) ;;
  *) exit 0 ;;
esac

# ファイルの属するリポジトリへ移る。まだ無いディレクトリは、存在する祖先から探す。
abs="$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$file_path")"
dir="$(dirname "$abs")"
while [ ! -d "$dir" ]; do dir="$(dirname "$dir")"; done
root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || pwd -P)"
cd "$root"
rel="$(python3 -I -c 'import os,sys; print(os.path.relpath(sys.argv[1]))' "$abs")"

# in_scope <台帳>: 台帳の「テスト対象:」(全角コロン可)の glob に rel が一致するか。
# glob はリポジトリのルートからの相対パス。行が無い、またはテンプレートのまま(< を含む)
# なら未記入として全ファイルを対象にする。
in_scope() {
  python3 -I "$here/ledger_covers.py" "$1" "$rel"
}

ledger_dir="tasks/test-design"
[ -d "$ledger_dir" ] || exit 0

# 台帳が1つも無ければ対象外(このリポジトリ/タスクでは台帳運用をしていない)
ledgers="$(find "$ledger_dir" -maxdepth 1 -name '*.md' 2>/dev/null || true)"
[ -n "$ledgers" ] || exit 0

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    unchecked) printf 'test-design 0段ゲート: %s に未チェック(- [ ] T-...)が残っている。手法割り当てとテスト名を埋めて [x] にしてから実装へ進め。\n' "$2" ;;
    gap) printf 'test-design 0段ゲート: %s の T-ID 連番に欠番がある(T-%s..T-%s のうち %s 件)。抜けを埋めるか採番し直せ。\n' "$2" "$3" "$4" "$5" ;;
    no_feature) printf 'test-design 0段ゲート: tasks/loopeng/ に .feature があるが、どの台帳にも出典として転記されていない。loopeng-gherkin の正常系シナリオを T-ID として台帳に転記してから実装へ進め。\n' ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

block() { # block <code> [args...]: 文言を stderr に出して exit 2
  msg "$@" >&2
  exit 2
}

for ledger in $ledgers; do
  in_scope "$ledger" || continue
  # 「## 台帳」以降だけを対象にする(テンプレ見出しの例を拾わないため)
  body="$(awk '/^## 台帳/{f=1;next} /^## /{if(f)exit} f' "$ledger")"
  [ -n "$body" ] || continue

  if printf '%s' "$body" | grep -qE '^\s*- \[ \] T-'; then
    block unchecked "$ledger"
  fi

  ids="$(printf '%s' "$body" | grep -oE 'T-[0-9]+' | sort -u || true)"
  [ -n "$ids" ] && {
    nums="$(printf '%s' "$ids" | sed 's/^T-0*//' | sort -n)"
    first="$(printf '%s' "$nums" | head -n1)"
    last="$(printf '%s' "$nums" | tail -n1)"
    count="$(printf '%s\n' "$nums" | grep -c .)"
    expected=$((last - first + 1))
    if [ "$count" -ne "$expected" ]; then
      block gap "$ledger" "$first" "$last" "$count"
    fi
  }
done

# loopeng-gherkin の成果物(.feature)があるのに、どの台帳にも1件も転記されていなければブロック。
# 出典欄に "<対象>.feature" と書く規約(loopeng-gherkin/SKILL.md・test-extract/SKILL.md 参照)。
features="$(find tasks/loopeng -maxdepth 1 -name '*.feature' 2>/dev/null || true)"
if [ -n "$features" ]; then
  transcribed=0
  for f in $features; do
    base="$(basename "$f")"
    # shellcheck disable=SC2086 # $ledgers は改行区切りの台帳一覧。上の for と同じく語分割して複数ファイルを渡す
    if grep -qF "$base" $ledgers 2>/dev/null; then
      transcribed=1
      break
    fi
  done
  [ "$transcribed" -eq 1 ] || block no_feature
fi

exit 0
