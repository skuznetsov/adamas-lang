#!/usr/bin/env bash
# Regression guard for module-super resolution through include chains.
#
# Array(Bool)#join comes from Indexable#join. Its `super(separator)` must resolve
# to Enumerable#join, not to Reference#join. The wrong owner produces an
# unlowered Reference#join(String)_super abort stub at runtime.
#
# Exit contract:
#   0 — fixed: Bool Array#join reaches Enumerable#join and prints the marker.
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
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array_bool_join_module_super.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
bools = [true, false, true]
joined = bools.join("|")

if joined == "true|false|true"
  puts "array_bool_join_module_super_ok"
else
  puts "array_bool_join_module_super_FAIL"
  puts joined
end
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

if grep -qF "array_bool_join_module_super_ok" "$RUN_LOG"; then
  echo "fixed: Array(Bool)#join resolves module super to Enumerable#join"
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
