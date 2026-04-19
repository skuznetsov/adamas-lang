#!/usr/bin/env bash
# Regression guard for small Hash linear scan lookup/update.
#
# V2 can lower stdlib `Hash#each_entry_with_index` blocks as real proc calls.
# The `return entry, index if ...` inside Hash's small-table linear scan must
# behave like a non-local return; otherwise entries are inserted but lookup and
# update scans always report "not found".
#
# Exit contract:
#   0 — fixed: String lookup and Int32 overwrite both behave correctly.
#   1 — reproduced: binary ran but did not print the fixed marker.
#   2 — invalid invocation (missing compiler arg).
#   >2 — unexpected compile/runtime failure.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_small_linear_scan.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
hs = {} of String => Int32
hs["one"] = 1
puts hs.size
puts hs.has_key?("one")
puts hs["one"]
hs["one"] = 9
puts hs.size
puts hs["one"]

hi = {} of Int32 => Int32
hi[1] = 7
puts hi.has_key?(1)
hi[1] = 9
puts hi.size
puts hi[1]

puts "hash_small_linear_scan_ok"
CR

compile_cmd=()
if [[ "$(basename "$COMPILER")" == "crystal" ]]; then
  compile_cmd=("$COMPILER" build "$SRC" -o "$BIN")
else
  compile_cmd=("$COMPILER" "$SRC" -o "$BIN")
fi

set +e
"${compile_cmd[@]}" >"$TMP_DIR/compile.out" 2>&1
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "unexpected: compile failed with status=$compile_status" >&2
  tail -20 "$TMP_DIR/compile.out" >&2
  exit 3
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

if grep -qF "hash_small_linear_scan_ok" "$RUN_LOG"; then
  echo "fixed: small Hash linear scan lookup/update works"
  cat "$RUN_LOG"
  exit 0
fi

if [[ $run_status -eq 0 ]]; then
  echo "reproduced: fixed marker missing despite exit 0" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "unexpected: abnormal exit ($run_status)" >&2
echo "--- run log tail ---" >&2
tail -20 "$RUN_LOG" >&2
exit 4
