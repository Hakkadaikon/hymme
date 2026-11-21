#!/usr/bin/env bash
# hooks/git-guard.sh の回帰テスト。要: python3, git。
set -euo pipefail

cd "$(dirname "$0")/.."
hook="$PWD/hooks/git-guard.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

msg() { # msg <code> [args...]: 端末に出すメッセージはここで引く
  case "$1" in
    pass) printf '合格   %s -> %s\n' "$2" "$3" ;;
    fail) printf '不合格 %s: exit %s(期待は %s)\n' "$2" "$3" "$4" ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

# gate <want-exit> <command>
gate() {
  local got=0
  python3 -I -c 'import json,sys; print(json.dumps({"tool_input": {"command": sys.argv[1]}}))' "$2" |
    (cd "$tmp" && bash "$hook") >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$1" ]; then
    msg pass "$2" "$got"
  else
    msg fail "$2" "$got" "$1"
    fail=1
  fi
}

git -C "$tmp" init -q

gate 0 'git status'
gate 2 'git rebase main'
gate 2 'git pull --rebase'
gate 0 'git rebase --abort'
gate 2 'git reset --hard HEAD~1'
gate 2 'git push --force'
gate 2 'git push -f origin work'
gate 2 'git push --force-with-lease'
gate 2 'git push origin +work'
gate 0 'git push --force-with-lease=work:0123abc origin work'
gate 2 'bash -c "git push -f"'
gate 2 'make test; git commit -m x'
gate 2 'make test | tail -3 && git commit -m x'
gate 0 'make test && git commit -m x'
gate 0 'git commit -m "docs: mention git rebase and git push --force"'

# arm marker があれば rebase と reset は通る(30分以内)
date +%s >"$tmp/.git/rebase-flow.armed"
date +%s >"$tmp/.git/reset-flow.armed"
gate 0 'git rebase main'
gate 0 'git reset --soft HEAD~1'
echo 1 >"$tmp/.git/rebase-flow.armed"
gate 2 'git rebase main'

exit "$fail"
