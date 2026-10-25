#!/usr/bin/env bash
# TLC の前段の静的検査。TLC(モデル検査・mutation oracle)を回す前に必ず通す。
#
#   tla_lint.sh <spec.tla>
#
# 1. SANY で構文・意味解析(未定義の名前、引数の数、レベルの誤り)。
#    SANY はエラーがあっても exit 0 を返すので、出力の "*** Errors" / "***Parse Error***" / "Fatal errors" で判定する。
# 2. spec に Apalache の型注釈(@type:)があれば `apalache-mc typecheck` で型検査。
#    注釈が無い spec はスキップする(注釈なしの spec では typecheck が必ず落ちるため)。
#
# exit: 0 = 通過、1 = spec にエラー(直してから TLC へ)、2 = 使い方・ツール不在。
set -uo pipefail

spec="${1:-}"
[ -n "$spec" ] && [ -f "$spec" ] || {
  echo "tla_lint: no such spec: ${spec:-<none>}" >&2
  exit 2
}
# 判定に使うコマンドが無いと、エラーを見逃して通してしまう。先に確かめる。
for c in grep dirname basename mktemp tail; do
  command -v "$c" >/dev/null 2>&1 || {
    echo "tla_lint: \`$c\` が PATH に無い" >&2
    exit 2
  }
done
dir="$(cd "$(dirname "$spec")" && pwd)"
base="$(basename "$spec")"

if command -v sany >/dev/null 2>&1; then
  sany_cmd=(sany)
elif [ -n "${TLA_JAR:-}" ] && command -v java >/dev/null 2>&1; then
  sany_cmd=(java -cp "$TLA_JAR" tla2sany.SANY)
else
  echo "tla_lint: no \`sany\` on PATH and no java+TLA_JAR fallback" >&2
  exit 2
fi

out="$(cd "$dir" && "${sany_cmd[@]}" "$base" 2>&1)"
if grep -qE '\*\*\* Errors|\*\*\*Parse Error\*\*\*|Fatal errors' <<<"$out"; then
  echo "== SANY: $spec に構文/意味エラー。直してから TLC を回す ==" >&2
  grep -vE '^(Parsing file|Semantic processing of module|Linting of module)' <<<"$out" >&2
  exit 1
fi
echo "SANY ok: $spec"

if grep -q '@type:' "$spec"; then
  command -v apalache-mc >/dev/null 2>&1 || {
    echo "tla_lint: @type 注釈があるが apalache-mc が無い" >&2
    exit 2
  }
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/tla_lint.XXXXXX")"
  trap 'rm -rf "$scratch"' EXIT
  if ! out="$(cd "$dir" && apalache-mc --out-dir="$scratch" typecheck "$base" 2>&1)"; then
    if grep -q 'EXITCODE: ERROR' <<<"$out"; then
      echo "== Apalache typecheck: $spec に型エラー。直してから TLC を回す ==" >&2
      grep -E '[Ee]rror|EXITCODE|^\[' <<<"$out" >&2
      exit 1
    fi
    echo "tla_lint: apalache-mc が型検査の前に失敗した(spec の誤りではない)" >&2
    tail -n 20 <<<"$out" >&2
    exit 2
  fi
  echo "Apalache typecheck ok: $spec"
else
  echo "Apalache typecheck: skipped (no @type annotations in $spec)"
fi
