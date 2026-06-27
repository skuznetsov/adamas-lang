#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/int-remainder-mixed-width.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN="$TMP_DIR/int_remainder_mixed_width"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"
STDOUT_LOG="$TMP_DIR/stdout.log"

"$COMPILER" "$ROOT_DIR/regression_tests/int_remainder_mixed_width_repro.cr" -o "$BIN" >"$COMPILE_LOG" 2>&1
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1

awk '/^=== STDOUT ===$/ {capture=1; next} /^=== STDERR ===$/ {capture=0} capture {print}' "$RUN_LOG" >"$STDOUT_LOG"

expected=$'1\n2\n1\n2'
actual="$(cat "$STDOUT_LOG")"
if [[ "$actual" != "$expected" ]]; then
  echo "FAIL: mixed-width Int32#remainder/Hasher.reduce_num expected:" >&2
  printf '%s\n' "$expected" >&2
  echo "actual:" >&2
  printf '%s\n' "$actual" >&2
  echo "compiler log:" >&2
  cat "$COMPILE_LOG" >&2
  echo "runtime log:" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "int_remainder_mixed_width_ok"
