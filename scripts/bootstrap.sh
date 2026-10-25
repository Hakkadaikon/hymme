#!/usr/bin/env bash
# Bootstrap the hymme skill toolchain.
#
#   ./scripts/bootstrap.sh            # nix develop (enter a dev shell with the tools)
#   ./scripts/bootstrap.sh install    # nix profile install .#skill-tools (persist into profile)
#
# Installs Determinate Nix first if `nix` is missing. The Nix install is a
# system-level change (needs sudo, adds /nix, edits your shell rc), so it
# prompts before running unless HYMME_ASSUME_YES=1.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-develop}"

msg() { # msg <code> [args...]: 端末に出す文言はここで引く
  case "$1" in
    not_tty) printf '端末から実行されていない。続けるなら HYMME_ASSUME_YES=1 を付けて再実行する\n' ;;
    confirm) printf '%s [y/N] ' "$2" ;;
    no_nix) printf 'Nix が見つからない\n' ;;
    ask_install) printf 'Determinate Nix をインストールするか(システム全体に入る。sudo が要る)' ;;
    aborted) printf '中止した。Nix を自分で入れてから再実行する\n' ;;
    not_on_path) printf 'Nix は入ったが PATH に無い。新しいシェルを開いて再実行する\n' ;;
    usage) printf '使い方: %s [develop|install]\n' "$2" ;;
    *) printf '未知のメッセージコード: %s\n' "$1" >&2 ;;
  esac
}

confirm() {
  [ "${HYMME_ASSUME_YES:-}" = "1" ] && return 0
  [ -t 0 ] || {
    msg not_tty >&2
    return 1
  }
  read -r -p "$(msg confirm "$1")" a
  case "$a" in [yY] | [yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

ensure_nix() {
  if command -v nix >/dev/null 2>&1; then
    return 0
  fi
  msg no_nix
  confirm "$(msg ask_install)" || {
    msg aborted >&2
    exit 1
  }
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install
  # The installer adds Nix to new shells; load it into this one.
  # shellcheck disable=SC1091 # nix-daemon.sh は実行時にしか存在せず、静的には辿れない
  if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  command -v nix >/dev/null 2>&1 || {
    msg not_on_path >&2
    exit 1
  }
}

ensure_nix

# Determinate Nix enables flakes by default; pass the flag anyway for vanilla installs.
flags=(--extra-experimental-features "nix-command flakes")

case "$mode" in
  develop)
    exec nix "${flags[@]}" develop "$here"
    ;;
  install)
    exec nix "${flags[@]}" profile install "$here#skill-tools"
    ;;
  *)
    msg usage "$0" >&2
    exit 2
    ;;
esac
