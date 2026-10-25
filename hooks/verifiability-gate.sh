#!/usr/bin/env bash
# 検証容易性ゲート: 形式検証の入口(loop-outer/middle/inner、smt_oracle.py、trace_check.py、
# tasks/fv/<Name> での lake build)を叩く前に、tasks/verifiability/<Name>.md の台帳があり、
# verifiability.py の指標が全対象で通り(または理由付きの例外)、対象コードがあるなら
# reviewer の合格の行が [x] であることを検査する。満たさなければ exit 2 でブロックする。
# PreToolUse(matcher: Bash)。stdin に hook の JSON。
set -euo pipefail

payload="$(cat)"
# 入口の探し方は gate_targets.py(OK<TAB>台帳のルート<TAB>名前<TAB>種類 か BLOCK<TAB>理由 を出す)。
# -I: 作業中のリポジトリに json.py などがあっても読み込まない
if ! targets="$(printf '%s' "$payload" | python3 -I "$(dirname "$0")/gate_targets.py" 2>/dev/null)"; then
  # 解析できないときは、入口らしき語があれば止める(lake build は python が無くても動くので素通りさせない)
  printf '%s' "$payload" | grep -qE 'loop-(outer|middle|inner)|smt_oracle\.py|trace_check\.py|lake[^"]*build' || exit 0
  echo "検証容易性ゲート: コマンドを解析できなかった(python3 が無い、または解析の失敗)。検証の入口は止める。" >&2
  exit 2
fi
[ -n "$targets" ] || exit 0

block() {
  echo "検証容易性ゲート: $1" >&2
  exit 2
}

# 台帳のルートへ cd してから PATH を引き直すと、PATH の空要素や . でルートの偽物を拾うので、先に絶対パスにする
tool="$(command -v verifiability.py 2>/dev/null || true)"

while IFS=$'\t' read -r kind root name entry; do
  [ "$kind" = BLOCK ] && block "$root"
  ledger="$root/tasks/verifiability/${name}.md"
  [ -f "$ledger" ] || block "台帳 $ledger が無い。コントローラが verifiability スキルの assets/verifiability-template.md をコピーし、検証する判定の関数を「## 対象」に書くか、写すコードが無ければ「対象コード無し: 理由」と書いてから進める(modeler/prover は台帳を書かずに BLOCKED で返す)。"

  # 写すコードが無い設計検証は、計測の道具が無くても通す。実ログの突き合わせは実装後の段なので、
  # 手元に実装が無い理由を「対象コード無し(実装後): 理由」と明示したときだけ通す。
  targets_sec="$(awk '/^## 対象[[:space:]]*$/{f=1;next} /^## /{f=0} f' "$ledger")"
  if ! printf '%s\n' "$targets_sec" | grep -qE '^- [^[:space:]]+::[^[:space:]]+'; then
    if [ "$entry" = trace_check ]; then
      printf '%s\n' "$targets_sec" | grep -qE '^対象コード無し\(実装後\)[:：][[:space:]]*[^[:space:]]' && continue
      block "$ledger は対象コードが無いが、実ログの突き合わせは実装後の段。対象の関数を「## 対象」に書き直すか、手元に実装が無い理由を「対象コード無し(実装後): 理由」と書く。"
    fi
    printf '%s\n' "$targets_sec" | grep -qE '^対象コード無し(\(実装後\))?[:：][[:space:]]*[^[:space:]]' && continue
  fi

  case "$tool" in /*) ;; *) block "verifiability.py が PATH に(絶対パスで)無い。hymme の skill-tools を入れてから進め(指標を測れないまま検証へ進ませない)。" ;; esac
  out="$(cd "$root" && "$tool" "tasks/verifiability/${name}.md" 2>&1)" || block "$ledger の指標が通らない。判定を小さな純粋関数へ切り出して再計測するか、理由付きの例外を書け:
$out"

  # 指標で測れない点(対象の選び方・例外の妥当性・振る舞いの保全)は reviewer の合格が要る
  awk '/^## レビュー[[:space:]]*$/{f=1;next} /^## /{f=0} f' "$ledger" | grep -qE '^[[:space:]]*- \[[xX]\] レビュー合格' ||
    block "$ledger の「## レビュー」に合格の行(- [x] レビュー合格: ...)が無い。hymme:verifiability-reviewer との往復で合格を得てから進め。"
done <<<"$targets"
exit 0
