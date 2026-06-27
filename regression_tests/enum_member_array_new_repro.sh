#!/usr/bin/env bash
# Regression: Array.new(size, Enum::Member) must infer Array(Enum), not
# Array(Enum::Member). The singleton-member owner shape previously produced
# unresolved Array/member call targets and, in self-hosted compiler code,
# a null-buffer filled array.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum_member_array_new.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$SRC" <<'CR'
enum E : UInt8
  A = 1
  B = 2
end

a = Array.new(2, E::A)
a[0] = E::B
puts "RESULT=#{a.size},#{a[0] == E::B}"
STDOUT.flush
CR

set +e
ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:-} -fsanitize=address" \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 "$SRC" -o "$BIN" >"$COMPILE_LOG" 2>&1
compile_status=$?
set -e
if [[ $compile_status -ne 0 ]]; then
  echo "FAIL: compile failed (status $compile_status)"
  cat "$COMPILE_LOG"
  exit 2
fi

set +e
ASAN_OPTIONS='detect_leaks=0:abort_on_error=1:symbolize=1' \
  "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

result_line="$(grep -E '^RESULT=' "$RUN_LOG" | head -1 || true)"
if [[ $run_status -eq 0 && "$result_line" == "RESULT=2,true" ]]; then
  echo "PASS: enum-member Array.new infers the enum owner"
  exit 0
fi

echo "FAIL: enum-member Array.new still miscompiled"
echo "run status: $run_status"
cat "$RUN_LOG"
exit 1
