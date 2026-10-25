#!/usr/bin/env bash
# hymme 開発用: agents/*-reviewer.md のうち出力フォーマット節に `## チェックリスト` を持つものについて、
# 本文(## 必須ゲート 〜 ## 出力フォーマット)の太字見出し語とチェックリストの項目名が
# 同じ順で 1 対 1 に一致するか、件数の直書きが無いかを検査する。
# チェックリストがあるのに ## 必須ゲート 節が無ければエラー。この形式を持たない reviewer は素通りする。
# usage: check-reviewer-checklist.sh [file...]  (省略時は agents/*-reviewer.md)
set -euo pipefail
# 件数直書き検出の近さの窓をバイトでなく文字で数える
export LC_ALL=C.UTF-8

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    no_file) printf '%s: ファイルが無い\n' "$2" ;;
    no_gate) printf '%s: チェックリストがあるのに ## 必須ゲート 節が無い\n' "$2" ;;
    mismatch) printf '%s: 本文の見出し語とチェックリストの項目名が一致しない(< 本文 / > チェックリスト)\n' "$2" ;;
    count) printf '%s: チェックリストの件数を数字で直書きしている(上の行)\n' "$2" ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

[ "$#" -gt 0 ] || set -- "$(dirname "$0")"/../agents/*-reviewer.md

status=0
for f in "$@"; do
  [ -f "$f" ] || {
    msg no_file "$f" >&2
    status=1
    continue
  }
  awk '/^## 出力フォーマット/{fmt=1} fmt && /^## チェックリスト/{found=1} END{exit !found}' "$f" || continue
  if ! grep -q '^## 必須ゲート' "$f"; then
    msg no_gate "$f" >&2
    status=1
    continue
  fi

  body="$(awk '/^## 必須ゲート/{in_sec=1} /^## 出力フォーマット/{in_sec=0} in_sec' "$f" |
    sed -nE 's/^([0-9]+\.|-) \*\*([^*]+)\*\*.*/\2/p')"
  checklist="$(awk '/^## 出力フォーマット/{fmt=1} fmt && /^## チェックリスト/{in_sec=1;next} in_sec && /^```/{exit} in_sec' "$f" |
    sed -nE 's/^- (.*[^ ]) +: .*/\1/p')"

  if [ "$body" != "$checklist" ]; then
    msg mismatch "$f" >&2
    diff <(printf '%s\n' "$body") <(printf '%s\n' "$checklist") >&2 || true
    status=1
  fi

  # 全桁が 0/1 の数(10, 11 等)は拾えないが、項目数でこの形はまず出ないため許容する。
  if grep -nE '[2-9][0-9]*(項目|行).{0,20}(チェックリスト|項目一覧)|((チェックリスト|項目一覧).{0,20}[2-9][0-9]*(項目|行))' "$f" >&2; then
    msg count "$f" >&2
    status=1
  fi
done
exit "$status"
