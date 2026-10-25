#!/usr/bin/env bash
# skill-tools の bin に loopeng/bin のスクリプトが入り、PATH から呼べることの回帰テスト。
# 使い方: loopeng-tools.test.sh <skill-tools の bin ディレクトリ>
set -euo pipefail

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    usage) printf '使い方: loopeng-tools.test.sh <bin ディレクトリ>' ;;
    ok) printf '合格   %s\n' "$2" ;;
    ng) printf '不合格 %s\n' "$2" ;;
    installed) printf '%s が入っている' "$2" ;;
    missing) printf '%s が無い' "$2" ;;
    failed) printf '%s が失敗した' "$2" ;;
    imports) printf 'tla_mutate_oracle.py をモジュールとして読み込める' ;;
    no_import) printf 'tla_mutate_oracle.py をモジュールとして読み込めない' ;;
    want_exit) printf '%s: exit %s(期待は %s)' "$2" "$3" "$4" ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}
bin="${1:?$(msg usage)}"
fail=0
ok() { msg ok "$1"; }
ng() {
  msg ng "$1"
  fail=1
}

for tool in tla_mutate_oracle.py trace_to_gherkin.py feature_to_c.py trace_check.py smt_oracle.py verifiability.py tla_lint.sh; do
  if [ -x "$bin/$tool" ]; then ok "$(msg installed "$tool")"; else ng "$(msg missing "$tool")"; fi
done

# python のスクリプトが PATH から起動できる(shebang が nix の python を指す)
if "$bin/tla_mutate_oracle.py" --help >/dev/null 2>&1; then ok 'tla_mutate_oracle.py --help'; else ng "$(msg failed 'tla_mutate_oracle.py --help')"; fi
for tool in trace_to_gherkin.py feature_to_c.py trace_check.py smt_oracle.py verifiability.py; do
  if "$bin/$tool" --selfcheck >/dev/null 2>&1; then ok "$tool --selfcheck"; else ng "$(msg failed "$tool --selfcheck")"; fi
done

# モジュールとして読み込める(リポジトリ側のツールが import して使う)
if python3 -c "import importlib.util,sys; s=importlib.util.spec_from_file_location('o', sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); assert m.MUTATIONS" "$bin/tla_mutate_oracle.py"; then
  ok "$(msg imports)"
else
  ng "$(msg no_import)"
fi

# tla_lint.sh は PATH の sany で spec を判定する(正しい spec は 0、壊れた spec は 1)
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp" _JAVA_OPTIONS="-Djava.io.tmpdir=$tmp"
printf '%s\n' '---- MODULE Good ----' 'VARIABLE x' 'Init == x = 0' "Next == x' = x" '====' >"$tmp/Good.tla"
printf '%s\n' '---- MODULE Bad ----' 'VARIABLE x' 'Init == x = = 0' '====' >"$tmp/Bad.tla"
lint() { # lint <want-exit> <spec>
  local got=0
  PATH="$bin:$PATH" tla_lint.sh "$tmp/$2.tla" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$1" ]; then ok "tla_lint.sh $2 -> $got"; else ng "$(msg want_exit "tla_lint.sh $2" "$got" "$1")"; fi
}
lint 0 Good
lint 1 Bad

exit "$fail"
