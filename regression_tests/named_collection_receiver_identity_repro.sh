#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SOURCE="$ROOT_DIR/regression_tests/named_collection_receiver_identity_probe.cr"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_named_collection_receiver.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found or not executable: $COMPILER" >&2
  exit 2
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
  "$SOURCE" --no-prelude -o "$WORK_DIR/repro" >"$WORK_DIR/compile.log" 2>&1; then
  cat "$WORK_DIR/compile.log" >&2
  exit 1
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/runtime.log" 2>&1; then
  cat "$WORK_DIR/runtime.log" >&2
  exit 1
fi

echo "PASS: relative and absolute named collection receivers preserve nested generic identity"
