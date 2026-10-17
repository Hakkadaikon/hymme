#!/usr/bin/env bash
# hymme:*-reviewer agent 定義の自己整合性ゲート: agents/*-reviewer.md のうち出力フォーマットに
# `## チェックリスト` 形式(本スクリプトが前提とする構造)を持つもの(現時点では
# loop-engineering-reviewer のみ)への Write/Edit の後に、「必須ゲート + スキル別チェック +
# 横断チェック」の太字見出し数と、出力フォーマットのチェックリスト行数が一致しているかを
# 機械的に検査する。この形式を持たない *-reviewer は構造が違うとみなして素通りする
# (詳細は下の guard のコメントを参照)。
#
# 背景: WebExploratoryQA の往復レビューで、プロンプト文言(「件数を数えて書かない」等)だけでは
# 項目数の drift を防げず、diff-review で何度も同種の不一致(13項目のつもりが14項目だった等)を
# 後から指摘されるループになった。プロンプトの指示を機械的なゲートに置き換える。
#
# 検査1: 本文(## 必須ゲート 〜 ## 出力フォーマット)の `^[0-9]+\. \*\*` + `^- \*\*` の太字見出し数と、
#        出力フォーマット内チェックリストの `^- ` 行数が一致しているか。
# 検査2: 本文中に「N項目」「N行」のような件数の直書きが復活していないか(規範的な「1〜2行」等は許容)。
#
# 不一致なら exit 2 で検出し、その場で Claude へ差し戻す。書き込み自体は PostToolUse なので
# 既に完了しており、巻き戻せない(次のターンで自分で直させる形になる)。
# 対象外のファイル(reviewer 定義でない agent)は素通りする。
# PostToolUse(matcher: Write|Edit)。stdin に hook の JSON。
set -euo pipefail

payload="$(cat)"
file_path="$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null || true)"
[ -n "$file_path" ] || exit 0

case "$file_path" in
  */agents/*-reviewer.md) ;;
  *) exit 0 ;;
esac
[ -f "$file_path" ] || exit 0

# このゲートは「出力フォーマット節の中に `## チェックリスト` という専用見出しを持つ」形式の
# reviewer だけを対象にする(現時点では loop-engineering-reviewer のみ)。
# 「必須ゲート」節の有無だけで判定すると、まだこの形式へ移行していない他の *-reviewer
# (formal-verification-reviewer, test-design-reviewer 等、出力フォーマット節に別の fenced block
# ——違反報告の雛形——を持つだけのもの)に誤爆する(実測済み: body/checklist 件数が噛み合わず
# 誤字修正ですら Write/Edit がブロックされる)。下の3つの grep/awk 判定を全て満たすかどうかで
# 判定し、満たさないファイルは構造が違うとみなして素通りする。
grep -q '^## 必須ゲート' "$file_path" || exit 0
grep -q '^## 出力フォーマット' "$file_path" || exit 0
# `## チェックリスト` は「出力フォーマット」節の中に実在する専用見出しとして存在するかを見る
# (ファイル全体への grep だと、将来別の意味でこの見出しを使う reviewer に誤爆しうる)。
awk '/^## 出力フォーマット/{f=1} f && /^## チェックリスト/{found=1} END{exit !found}' "$file_path" || exit 0

flag() { echo "reviewer チェックリスト整合ゲート ($file_path): $1" >&2; exit 2; }

# 本文側(## 必須ゲート 〜 ## 出力フォーマットの手前)の太字見出し項目数。
body="$(awk '/^## 必須ゲート/{f=1} /^## 出力フォーマット/{f=0} f' "$file_path")"
body_count="$(printf '%s\n' "$body" | grep -cE '^([0-9]+\.|-) \*\*' || true)"

# チェックリスト側(`## 出力フォーマット` 以降にある `## チェックリスト` 見出しから、
# 最初に閉じる fence までの範囲)の `- ` 行数(節見出し行 `[必須ゲート]` 等は除く)。
# guard が「`## 出力フォーマット` 以降に `## チェックリスト` が実在するか」を節スコープで
# 判定しているのに合わせ、抽出側も同じスコープに限定する(そうしないと、出力フォーマット節より
# 前に別用途で `## チェックリスト` という見出しを持つファイルに対して、guard は通過するのに
# 抽出はその手前の見出しにアンカーして誤カウントする)。
checklist_block="$(awk '/^## 出力フォーマット/{g=1} g && /^## チェックリスト/{f=1;next} f && /^```/{exit} f' "$file_path")"
checklist_count="$(printf '%s\n' "$checklist_block" | grep -cE '^- ' || true)"

if [ "$body_count" -eq 0 ] || [ "$checklist_count" -eq 0 ]; then
  # 構造を見つけられなければ判定不能。誤爆を避けて素通り(別の手段で見るしかない)。
  exit 0
fi

if [ "$body_count" -ne "$checklist_count" ]; then
  flag "本文の太字見出し項目数($body_count)とチェックリストの行数($checklist_count)が一致しない。項目を追加・削除したら両方を揃えること。"
fi

# 件数の直書きが復活していないかの簡易検出。「1行ずつ」「1項目でも」のような決まり文句は
# 対象外にし、2以上の具体的な個数(「13項目」「14行」等)がチェックリスト/項目一覧と同じ行に
# 出てくる場合だけ拾う(誤爆回避優先。1件でも見つかれば十分なので全件検出はしない。
# 全桁が0/1の数(10, 11, 100等)は検出できないが、現実的な項目数でこの形はまず出ないため許容する)。
if grep -nE '[2-9][0-9]*(項目|行).{0,20}(チェックリスト|項目一覧)|((チェックリスト|項目一覧).{0,20}[2-9][0-9]*(項目|行))' "$file_path" >/dev/null; then
  flag "チェックリストの項目数・行数を具体的な数字で直書きしている行が見つかった。件数は本文の見出しから動的に数える形にし、固定の数字を書かない。"
fi

exit 0
