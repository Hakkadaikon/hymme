#!/usr/bin/env bash
# check-doc-refs.py の回帰テスト。現行のリポジトリが通ることと、3 種の誤りをそれぞれ止めることを見る。
set -euo pipefail

cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

expect() { # expect <exit> <stderr に含む文字列> <名前> <root>
  local out code=0
  out="$(python3 scripts/check-doc-refs.py "$4" 2>&1)" || code=$?
  if [ "$code" = "$1" ] && { [ -z "$2" ] || grep -qF -- "$2" <<<"$out"; }; then
    printf '合格   %s\n' "$3"
  else
    printf '不合格 %s (exit=%s)\n%s\n' "$3" "$code" "$out"
    fail=1
  fi
}

expect 0 '' repo .

mk() { # mk <名前>: 作業コピーを作ってパスを返す
  mkdir -p "$tmp/$1"
  cp -R README.md agents skills hooks "$tmp/$1/"
  find "$tmp/$1" -exec chmod u+w {} +
  printf '%s' "$tmp/$1"
}

r="$(mk unknown)"
printf '\nhymme:no-such-agent を呼ぶ。\n' >>"$r/README.md"
expect 1 'hymme:no-such-agent という agent / スキルは無い' unknown "$r"

r="$(mk hidden)"
printf '\nhymme:test-extract を Skill ツールで呼ぶ。\n' >>"$r/README.md"
expect 1 'hymme:test-extract は一覧から隠したスキル' hidden "$r"

r="$(mk link)"
printf '\n[切れたリンク](../nowhere/SKILL.md)\n' >>"$r/skills/test-design/SKILL.md"
expect 1 'リンク先が無い: ../nowhere/SKILL.md' broken-link "$r"

r="$(mk path)"
# shellcheck disable=SC2016 # 変数名そのものの文字列を書き込む
printf '\n${CLAUDE_PLUGIN_ROOT}/skills/nowhere/SKILL.md を Read する。\n' >>"$r/README.md"
expect 1 'プラグイン内のパスが無い: skills/nowhere/SKILL.md' missing-path "$r"

exit "$fail"
