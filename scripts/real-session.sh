#!/usr/bin/env bash
# 実システムでの確かめ: このリポジトリをプラグインとして読み込んだ Claude Code のセッションを1回動かし、
# hook が実際に検証の入口を止めることを確かめる(tasks/surface.md の確認のコマンド)。
# 使い方: real-session.sh   (exit 0: 止めた、1: 止めなかった、2: 動かせなかった)
# 要: claude(Claude Code)、git。トークンを少し使う。インストール済みの hymme は切り、この作業ツリーだけを読ませる。
# 証跡は tasks/evidence/real-session.log に残す(git 管理外)。
set -euo pipefail

msg() { # msg <code> [args...]: 端末に出すメッセージはここで引く
  case "$1" in
    no_claude) printf '実システムでの確かめ: claude が見つからない(CLAUDE_BIN で場所を渡せる)。\n' ;;
    stopped) printf '合格   実際のセッションで、承認の無い検証の入口が止まった\n' ;;
    not_stopped) printf '不合格 実際のセッションで、承認の無い検証の入口が止まらなかった。出力: %s\n' "$2" ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

root="$(cd "$(dirname "$0")/.." && pwd)"
claude="${CLAUDE_BIN:-$(command -v claude || true)}"
[ -n "$claude" ] || claude="$HOME/.local/bin/claude"
[ -x "$claude" ] || {
  msg no_claude >&2
  exit 2
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q -b main
git -C "$work" -c user.email=probe@example.com -c user.name=probe commit -q --allow-empty -m "chore: start"
git -C "$work" checkout -q -b work
mkdir -p "$work/tasks/loopeng"
cat >"$work/tasks/loopeng/Probe.tla" <<'EOF'
---- MODULE Probe ----
EXTENDS Naturals
VARIABLE c
Init == c = 0
Next == c < 2 /\ c' = c + 1
Inv == c <= 2
====
EOF
printf 'INIT Init\nNEXT Next\nINVARIANT Inv\n' >"$work/tasks/loopeng/Probe.cfg"
printf '# 抽出台帳\n\n## 台帳\n\n- [x] S-001 数える\n\n## 閉じる前のチェック\n\n- [x] 全 ID が [x]\n' >"$work/tasks/loopeng/Probe.extract.md"
cat >"$work/tasks/loopeng/Probe.claims.md" <<'EOF'
# Probe で確かめること

## 実証する項目

| 要件 | 示すこと | 示さないこと | 破れたときの害 |
|---|---|---|---|
| 2を超えて数えない | どう進めても数は2以下 | 2という上限が妥当か | 数が実際より多く見える |

## 有限にした範囲

- 無し: 数は0から2まで

## 扱わない領域

- 無し: 状態は数1つだけ
EOF

# 承認の無い一覧のまま、検証の入口を1回実行させる。hook が働いていれば「ユーザーの確認ゲート」で止まる。
prompt='Run exactly this one bash command and report the literal output or error, then stop: cd tasks/loopeng && tlc -deadlock Probe.tla'
out="$(cd "$work" && PATH="$root/loopeng/bin:$PATH" "$claude" -p "$prompt" --plugin-dir "$root" \
  --settings '{"enabledPlugins":{"hymme@hymme":false}}' --model haiku --allowedTools Bash </dev/null 2>&1 || true)"

mkdir -p "$root/tasks/evidence"
{
  date '+%Y-%m-%dT%H:%M:%S%z'
  git -C "$root" rev-parse HEAD
  printf '%s\n' "$out"
} >"$root/tasks/evidence/real-session.log"

if grep -q 'ユーザーの確認ゲート' <<<"$out"; then
  msg stopped
else
  msg not_stopped "$(printf '%s' "$out" | tail -c 300)"
  exit 1
fi
