#!/usr/bin/env bash
# skill-tools の bin に loopeng/bin のスクリプトが入り、PATH から呼べることの回帰テスト。
# 使い方: loopeng-tools.test.sh <skill-tools の bin ディレクトリ>
set -euo pipefail

bin="${1:?usage: loopeng-tools.test.sh <bin-dir>}"
fail=0
ok() { echo "ok   $1"; }
ng() {
  echo "FAIL $1"
  fail=1
}

for tool in tla_mutate_oracle.py trace_to_gherkin.py feature_to_c.py tla_lint.sh; do
  if [ -x "$bin/$tool" ]; then ok "$tool is installed"; else ng "$tool is missing"; fi
done

# python のスクリプトが PATH から起動できる(shebang が nix の python を指す)
if "$bin/tla_mutate_oracle.py" --help >/dev/null 2>&1; then ok 'tla_mutate_oracle.py --help'; else ng 'tla_mutate_oracle.py --help failed'; fi
for tool in trace_to_gherkin.py feature_to_c.py; do
  if "$bin/$tool" --selfcheck >/dev/null 2>&1; then ok "$tool --selfcheck"; else ng "$tool --selfcheck failed"; fi
done

# モジュールとして読み込める(リポジトリ側のツールが import して使う)
if python3 -c "import importlib.util,sys; s=importlib.util.spec_from_file_location('o', sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); assert m.MUTATIONS" "$bin/tla_mutate_oracle.py"; then
  ok 'tla_mutate_oracle.py imports as a module'
else
  ng 'tla_mutate_oracle.py does not import'
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
  if [ "$got" -eq "$1" ]; then ok "tla_lint.sh $2 -> $got"; else ng "tla_lint.sh $2: exit $got (want $1)"; fi
}
lint 0 Good
lint 1 Bad

exit "$fail"
