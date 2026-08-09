#!/usr/bin/env bash
# Install a stable link rather than copying the launcher. The launcher resolves
# the link back to this checkout, keeping it version-coupled to its private
# library without a second installed tree that can drift.

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

target="$BIN_DIR/gstack-register"
if [[ (-e "$target" || -L "$target") && ! -L "$target" ]]; then
  printf 'gstack-register: refusing to replace non-symlink path: %s\n' \
    "$target" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
ln -sfn "$ROOT/bin/gstack-register" "$target"

printf 'installed gstack-register to %s\n' "$target"
