#!/usr/bin/env bash
# diff-review: レビュー担当が指摘を実行で確かめる入口(作業ツリーは書き換えない)
#
# 使い方:
#   run-in-copy.sh <ref> <command> [<arg>...]
#
# <ref> を一時ディレクトリへ git worktree add --detach で取り出し、そのコピーの直下でコマンドを1つ実行して、コピーを消す。
# 終了コードはコマンドのものを返す(使い方の誤りと取り出しの失敗は 64)。
# コピーに入るのはコミット済みの内容だけ。未コミットの変更、未追跡のファイル、依存の導入先(node_modules など)は入らない。
# shortcut: コマンドの中身は縛らない(絶対パスで書けばコピーの外にも書ける)。防ぐのは作業ツリーでの誤った実行まで。
# レビュー担当を信用できない使い方をするなら、コンテナなどの隔離に替える。
set -euo pipefail

msg() { # msg <code> [args...]: 端末に出すメッセージはここで引く
  case "$1" in
    usage) sed -n '4,9p' "$0" | cut -c3- ;;
    no_repo) printf 'git リポジトリの中で実行する\n' ;;
    bad_ref) printf '%s をコピーに取り出せない(コミット、ブランチ、タグのどれかを渡す)\n' "$2" ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

if [ $# -lt 2 ]; then
  msg usage >&2
  exit 64
fi
ref="$1"
shift
root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  msg no_repo >&2
  exit 64
}
tmp="$(mktemp -d)"
cleanup() {
  git -C "$root" worktree remove --force "$tmp/w" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT
git -C "$root" worktree add --detach "$tmp/w" "$ref" >/dev/null 2>&1 || {
  msg bad_ref "$ref" >&2
  exit 64
}
cd "$tmp/w"
"$@"
