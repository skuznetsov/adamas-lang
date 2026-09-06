#!/usr/bin/env bash
# Early inference must preserve named container identity across globals/ivars.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named_collection_constant_identity.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 --no-prelude \
  "$ROOT_DIR/regression_tests/named_collection_constant_identity_repro.cr" \
  -o "$WORK_DIR/probe" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/probe" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo named_collection_constant_identity_repro_ok
