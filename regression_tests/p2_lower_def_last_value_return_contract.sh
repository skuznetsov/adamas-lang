#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SOURCE="$ROOT_DIR/regression_tests/stage2_staticarray_tuple_return_contract_repro.cr"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_lower_def_return.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "p2_lower_def_last_value_return_contract_failed: compiler is not executable: $COMPILER" >&2
  exit 2
fi

BIN="$TMP_DIR/repro"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 \
  "$SOURCE" -o "$BIN" >"$COMPILE_LOG" 2>&1
compile_rc=$?
set -e

if [[ $compile_rc -ne 0 ]]; then
  echo "p2_lower_def_last_value_return_contract_failed: compile failed rc=$compile_rc" >&2
  tail -120 "$COMPILE_LOG" >&2 || true
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_rc=$?
set -e

if [[ $run_rc -ne 0 ]]; then
  echo "p2_lower_def_last_value_return_contract_failed: run failed rc=$run_rc" >&2
  tail -120 "$RUN_LOG" >&2 || true
  exit 1
fi

if ! rg -q 'define ptr @make_bytes\(\)' "$BIN.ll" ||
   ! rg -q 'call ptr @make_bytes\(\)' "$BIN.ll"; then
  echo "p2_lower_def_last_value_return_contract_failed: make_bytes did not use a pointer return contract" >&2
  rg -n 'define .*@make_bytes|call .*@make_bytes' "$BIN.ll" >&2 || true
  exit 1
fi

echo "p2_lower_def_last_value_return_contract_ok"
