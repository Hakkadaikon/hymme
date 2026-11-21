#!/usr/bin/env bash
# collect-diff.sh manifest の回帰テスト。未追跡のエントリがディレクトリを指すシンボリックリンクでも落ちないこと。
# あわせて diff-reviewer の Bash の許可リスト(validate-readonly-bash.sh)と、写しの中での実行(run-in-copy.sh)を見る。
# 要: git, jq
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

scripts_dir="$(dirname "$script")"
run="$scripts_dir/run-in-copy.sh"

verdict() { # verdict <期待する終了コード> <名前> <レビュー担当が打つコマンド>
  local code=0
  jq -n --arg c "$3" '{tool_input: {command: $c}}' | bash "$scripts_dir/validate-readonly-bash.sh" >/dev/null 2>&1 || code=$?
  if [ "$code" = "$1" ]; then
    printf '合格   %s\n' "$2"
  else
    printf '不合格 %s (exit=%s)\n' "$2" "$code"
    exit 1
  fi
}

verdict 0 allow-git-read 'git diff HEAD~1 | head -5'
verdict 0 allow-run-in-copy "$run HEAD true"
verdict 2 deny-run-in-worktree 'pytest tests'
verdict 2 deny-worktree-add 'git worktree add --detach /tmp/x HEAD'
verdict 2 deny-redirect 'echo x > a.txt'
verdict 2 deny-chain-after-copy "$run HEAD true && touch a.txt"

# 写しの中で実行する: 終了コードを返し、作業ツリーにファイルを残さず、worktree を片付ける
code=0
bash "$run" HEAD sh -c 'test -f a.txt && touch made.txt && exit 7' || code=$?
if [ "$code" = 7 ] && [ ! -e made.txt ] && [ "$(git worktree list | wc -l)" -eq 1 ]; then
  printf '合格   run-in-copy-leaves-tree\n'
else
  printf '不合格 run-in-copy-leaves-tree (exit=%s)\n' "$code"
  exit 1
fi
code=0
bash "$run" no-such-ref true 2>/dev/null || code=$?
if [ "$code" = 64 ]; then
  printf '合格   run-in-copy-bad-ref\n'
else
  printf '不合格 run-in-copy-bad-ref (exit=%s)\n' "$code"
  exit 1
fi
