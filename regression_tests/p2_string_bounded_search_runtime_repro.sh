#!/usr/bin/env bash
# Runtime guard for Crystal String data searches. V2 backend helpers must not
# pass Crystal String payloads to libc strstr: payloads are length-delimited,
# not NUL-terminated, and self-hosted compiler hot paths search for "$$block".
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_string_bounded_search_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/string_bounded_search.cr"
BIN="$TMP_DIR/string_bounded_search"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat >"$SRC" <<'CR'
puts "Hidden.new".includes?("$$block")
puts "abc$$block".includes?("$$block")
puts "Hidden.new".index("$$block").nil?
puts "abc$$block".index("$$block")
puts "abc$$block".index("$$block", 4).nil?
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1536 "$SRC" -o "$BIN" >"$COMPILE_LOG" 2>&1
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 256 >"$RUN_LOG" 2>&1

if ! grep -Fq $'false\ntrue\ntrue\n3\ntrue' "$RUN_LOG"; then
  echo "p2 string bounded search regression: unexpected output" >&2
  cat "$COMPILE_LOG" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "p2_string_bounded_search_runtime_ok"
