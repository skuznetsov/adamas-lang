#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/tuple-equality-hash.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN="$TMP_DIR/tuple_equality_hash"
OUT="$TMP_DIR/out.txt"
ERR="$TMP_DIR/err.txt"
STDOUT="$TMP_DIR/stdout.txt"

"$COMPILER" "$ROOT_DIR/regression_tests/tuple_equality_hash_repro.cr" -o "$BIN" >"$ERR" 2>&1
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$OUT" 2>>"$ERR"
awk '/^=== STDOUT ===$/ {capture=1; next} /^=== STDERR ===$/ {capture=0} capture {print}' "$OUT" >"$STDOUT"

expected=$'true\nfalse\ntrue\nfalse'
actual="$(cat "$STDOUT")"
if [[ "$actual" != "$expected" ]]; then
  echo "FAIL: tuple equality/hash expected:" >&2
  printf '%s\n' "$expected" >&2
  echo "actual:" >&2
  printf '%s\n' "$actual" >&2
  echo "compiler/runtime stderr:" >&2
  cat "$ERR" >&2
  exit 1
fi

echo "tuple_equality_hash_ok"
