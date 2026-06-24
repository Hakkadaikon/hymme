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

confirm() {
  [ "${HYMME_ASSUME_YES:-}" = "1" ] && return 0
  [ -t 0 ] || { echo "Not a TTY; rerun with HYMME_ASSUME_YES=1 to proceed." >&2; return 1; }
  read -r -p "$1 [y/N] " a
  case "$a" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

ensure_nix() {
  if command -v nix >/dev/null 2>&1; then
    return 0
  fi
  echo "Nix not found."
  confirm "Install Determinate Nix (system-level, needs sudo)?" || {
    echo "Aborted. Install Nix yourself, then re-run." >&2; exit 1; }
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install
  # The installer adds Nix to new shells; load it into this one.
  # shellcheck disable=SC1091
  if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  command -v nix >/dev/null 2>&1 || {
    echo "Nix installed but not on PATH. Open a new shell and re-run." >&2; exit 1; }
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
    echo "usage: $0 [develop|install]" >&2
    exit 2
    ;;
esac
