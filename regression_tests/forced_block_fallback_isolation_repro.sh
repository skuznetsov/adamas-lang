#!/usr/bin/env bash
# A bypass force-lower started from an inline-yield frame (or from a Proc
# frame) used to refuse every yield-bearing callee. The `_block` fallback of
# a private `decode_frame(ip, &)` reached through its blockless wrapper
# `decode_frame(ip)` was therefore never lowered: the wrapper result stayed
# Void (the `if frame = ...` guard took the else arm) or an
# ExactResultPending survived to the caller ("pending source result").
# Prelude shape: Exception::CallStack.decode_backtrace_frame ->
# decode_frame(ip) -> decode_frame(ip, &), reached from an inline block,
# which broke prelude hello with the in-repo stdlib.
# The forced body now runs with the caller's yield context reset (depth
# counters, inline name stack, explicit Proc yield targets and return hints),
# so the callee's own `yield` binds to its block parameter and cannot borrow
# the caller's inline block.
# Expected outcomes are checked against original Crystal when CRYSTAL_BIN is set.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
FIXTURES="$ROOT_DIR/regression_tests/forced_block_fallback_isolation"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forced-block-fallback.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# name expected-exit
CASES=(
  "top_level_annotated 13"
  "top_level_unannotated 13"
  "method_annotated 13"
  "method_unannotated 13"
  "proc_literal 90"
  "nested_yield_method 90"
)

fail=0
for entry in "${CASES[@]}"; do
  read -r name want <<<"$entry"
  src="$FIXTURES/$name.cr"

  if [[ -n "$CRYSTAL_BIN" ]]; then
    if "$CRYSTAL_BIN" build --prelude=empty "$src" -o "$WORK_DIR/$name.orig" >"$WORK_DIR/$name.orig.log" 2>&1; then
      orig_out="$("$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 2>&1 || true)"
      orig="$(printf '%s\n' "$orig_out" | sed -n 's/^\[EXIT: \([0-9-]*\)\].*/\1/p' | tail -1)"
    else
      orig="reject"
    fi
    if [[ "$orig" != "$want" ]]; then
      echo "ORACLE_MISMATCH $name: original=$orig expected=$want"
      fail=1
      continue
    fi
  fi

  if "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$src" -o "$WORK_DIR/$name.bin" >"$WORK_DIR/$name.log" 2>&1 &&
     [[ -x "$WORK_DIR/$name.bin" ]]; then
    out="$("$SAFE_RUNNER" "$WORK_DIR/$name.bin" 5 256 2>&1 || true)"
    got="$(printf '%s\n' "$out" | sed -n 's/^\[EXIT: \([0-9-]*\)\].*/\1/p' | tail -1)"
  else
    got="compile-failure"
    sed -n '1,8p' "$WORK_DIR/$name.log"
  fi

  if [[ "$got" == "$want" ]]; then
    echo "PASS $name"
  else
    echo "FAIL $name: expected $want, got $got"
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  echo "forced block fallback isolation regression failed"
  exit 1
fi
echo "forced block fallback isolation regression passed"
