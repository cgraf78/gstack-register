#!/usr/bin/env bash
# Install a stable link rather than copying the launcher. The launcher resolves
# the link back to this checkout, keeping it version-coupled to its private
# library without a second installed tree that can drift.

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
ROOT=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

source="$ROOT/bin/gstack-register"
target="$BIN_DIR/gstack-register"
if [[ ! -f "$source" || ! -x "$source" ]]; then
  printf 'gstack-register: command source is not executable: %s\n' \
    "$source" >&2
  exit 1
fi
if [[ (-e "$target" || -L "$target") && ! -L "$target" ]]; then
  printf 'gstack-register: refusing to replace non-symlink path: %s\n' \
    "$target" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
ln -sfn "$source" "$target"

printf 'installed gstack-register to %s\n' "$target"
