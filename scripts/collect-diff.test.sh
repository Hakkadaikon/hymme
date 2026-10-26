#!/usr/bin/env bash
# collect-diff.sh manifest の回帰テスト。未追跡のエントリがディレクトリを指すシンボリックリンクでも落ちないこと。
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/skills/diff-review/scripts/collect-diff.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q -b main
git config user.email t@example.com
git config user.name t
printf 'a\n' >a.txt
git add a.txt
git commit -q -m init
base="$(git rev-parse HEAD)"
printf 'b\n' >>a.txt
git commit -q -am change
mkdir target
ln -s target result
printf 'x\ny\n' >new.txt

if out="$(bash "$script" manifest "$base" 2>&1)" && grep -q 'untracked_lines=2' <<<"$out"; then
  printf '合格   untracked-dir-symlink\n'
else
  printf '不合格 untracked-dir-symlink\n%s\n' "$out"
  exit 1
fi
