#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-owner-method-index.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat >"$SRC" <<'CR'
require "time"

# Keep two independent callers so the concrete generic owners are discovered
# in both orders during one compile.  The Hash array is populated and the
# Time array is empty, making the expected result sensitive to the selected
# Array(T)#fetch body rather than merely to successful linking.
def hash_first : Nil
  hashes = [] of Hash(String, UInt32)
  hashes << ({} of String => UInt32)
  locations = [] of Time::Location::ZoneTransition
  x = hashes[0]?
  y = locations[0]?
  puts x.nil? ? 0 : 1
  puts y.nil? ? 0 : 1
end

def time_first : Nil
  locations = [] of Time::Location::ZoneTransition
  hashes = [] of Hash(String, UInt32)
  hashes << ({} of String => UInt32)
  y = locations[0]?
  x = hashes[0]?
  puts y.nil? ? 0 : 1
  puts x.nil? ? 0 : 1
end

hash_first
time_first
CR

set +e
DEBUG_CALL_LOOKUP='Array(Time::Location::ZoneTransition)#fetch' \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
  "$SRC" -o "$OUT" >"$LOG" 2>&1
compile_rc=$?
set -e

echo "compiler: $COMPILER"
echo "compile_rc: $compile_rc"

if [[ $compile_rc -ne 0 ]]; then
  tail -80 "$LOG" >&2 || true
  echo "FAIL: generic-owner lookup probe did not compile" >&2
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 30 1024 >"$RUN_LOG" 2>&1
run_rc=$?
set -e
if [[ $run_rc -ne 0 ]]; then
  cat "$RUN_LOG" >&2
  echo "FAIL: linked generic-owner lookup probe did not run" >&2
  exit 1
fi

actual_stdout="$(awk '
  /^=== STDOUT ===$/ { capture = 1; next }
  /^=== STDERR ===$/ { capture = 0 }
  capture { print }
' "$RUN_LOG")"
if [[ "$actual_stdout" != $'1\n0\n0\n1' ]]; then
  cat "$RUN_LOG" >&2
  echo "FAIL: linked probe stdout was not exactly 1\\n0\\n0\\n1" >&2
  exit 1
fi

if rg -q '\[CALL_LOOKUP_' "$LOG"; then
  if rg -q '\[CALL_LOOKUP_SELECTED\].*func=Array\(Time::Location::ZoneTransition\)#fetch.*best=Array\(Hash\(String, UInt32\)\)#fetch' "$LOG"; then
    echo "FAIL: concrete Time array lookup selected the Hash array sibling" >&2
    rg -n 'CALL_LOOKUP_(OVERLOADS|SELECTED).*Array' "$LOG" >&2 || true
    exit 1
  fi
  echo "trace_guard=checked"
else
  echo "trace_guard=unavailable"
fi

echo "PASS: concrete generic owners stay isolated in both discovery orders"
