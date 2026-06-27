#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SOURCE="$ROOT_DIR/regression_tests/combined/test_no_prelude_interpolation.cr"
TMP_DIR="$(mktemp -d /tmp/p2_generated_stage2_interp_XXXXXX)"
GENERATED_S2="$TMP_DIR/generated_s2"
BUILD_LOG="$TMP_DIR/build.log"
SMOKE_LOG="$TMP_DIR/smoke.log"
RUN_LOG="$TMP_DIR/run.log"
SMOKE_BIN="$TMP_DIR/no_prelude_interp"

cleanup() {
  if [[ "${KEEP_TMP:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "[p2_generated_stage2_no_prelude_interp] kept tmp: $TMP_DIR" >&2
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "p2_generated_stage2_no_prelude_interp_failed: compiler not found: $COMPILER" >&2
  exit 2
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 420 4096 \
  "$ROOT_DIR/src/adamas.cr" -o "$GENERATED_S2" >"$BUILD_LOG" 2>&1
build_status=$?
set -e

if [[ $build_status -ne 0 ]]; then
  echo "p2_generated_stage2_no_prelude_interp_failed: generated stage2 build exited $build_status" >&2
  tail -120 "$BUILD_LOG" >&2 || true
  exit 1
fi

if [[ ! -x "$GENERATED_S2" ]]; then
  echo "p2_generated_stage2_no_prelude_interp_failed: missing generated stage2 compiler" >&2
  tail -80 "$BUILD_LOG" >&2 || true
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$GENERATED_S2" 60 1024 \
  "$SOURCE" --no-prelude -o "$SMOKE_BIN" >"$SMOKE_LOG" 2>&1
smoke_status=$?
set -e

if [[ $smoke_status -ne 0 ]]; then
  if grep -Fq 'STUB CALLED: Adamas::MIR::LLVMIRGenerator#interpolation_i32_arg' "$SMOKE_LOG"; then
    echo "p2_generated_stage2_no_prelude_interp_failed: interpolation_i32_arg materialized as a live stub" >&2
  fi
  echo "p2_generated_stage2_no_prelude_interp_failed: generated compiler compile-smoke exited $smoke_status" >&2
  tail -120 "$SMOKE_LOG" >&2 || true
  exit 1
fi

if grep -Eq 'STUB CALLED:|error\[E[0-9]+\]:' "$SMOKE_LOG"; then
  if grep -Fq 'STUB CALLED: Adamas::MIR::LLVMIRGenerator#interpolation_i32_arg' "$SMOKE_LOG"; then
    echo "p2_generated_stage2_no_prelude_interp_failed: interpolation_i32_arg materialized as a live stub" >&2
  fi
  echo "p2_generated_stage2_no_prelude_interp_failed: unexpected runtime or semantic failure" >&2
  tail -120 "$SMOKE_LOG" >&2 || true
  exit 1
fi

if [[ ! -x "$SMOKE_BIN" ]]; then
  echo "p2_generated_stage2_no_prelude_interp_failed: missing no-prelude interpolation binary" >&2
  tail -120 "$SMOKE_LOG" >&2 || true
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$SMOKE_BIN" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  echo "p2_generated_stage2_no_prelude_interp_failed: generated no-prelude binary exited $run_status" >&2
  tail -120 "$RUN_LOG" >&2 || true
  exit 1
fi

if ! grep -q 'noprelude_interp_ok' "$RUN_LOG"; then
  echo "p2_generated_stage2_no_prelude_interp_failed: missing runtime success signal" >&2
  tail -120 "$RUN_LOG" >&2 || true
  exit 1
fi

echo "p2_generated_stage2_no_prelude_interp_ok"
