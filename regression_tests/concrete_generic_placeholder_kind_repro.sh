#!/usr/bin/env bash
# Concrete declarations upgrade cached generic placeholders without changing identity.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SPEC_ROOT="${ADAMAS_SPEC_ROOT:-$ROOT_DIR}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-placeholder-kind.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$SPEC_ROOT"
env CRYSTAL_CACHE_DIR="$WORK_DIR/cache" \
  "$ROOT_DIR/scripts/run_safe.sh" "$CRYSTAL" 180 12288 \
  spec --no-color --link-flags=-fuse-ld=/usr/bin/ld \
  spec/hir/concrete_generic_placeholder_kind_spec.cr
printf 'PASS: cached generic placeholders retain identity and declared class/struct kind\n'
