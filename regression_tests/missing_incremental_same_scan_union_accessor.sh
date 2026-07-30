#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT_DIR/regression_tests/missing_incremental_same_scan_union_accessor.cr"
TMP_DIR="$(mktemp -d /tmp/adamas_same_scan_union_accessor.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CRYSTAL_BIN="${CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
PROBE_BIN="$TMP_DIR/probe"
BUILD_LOG="$TMP_DIR/build.log"
RUN_LOG="$TMP_DIR/run.log"

CRYSTAL_CACHE_DIR="$TMP_DIR/cache" \
  "$ROOT_DIR/scripts/run_safe.sh" "$CRYSTAL_BIN" 180 6144 \
  build "$SOURCE" -o "$PROBE_BIN" --error-trace >"$BUILD_LOG" 2>&1
"$ROOT_DIR/scripts/run_safe.sh" "$PROBE_BIN" 30 2048 >"$RUN_LOG" 2>&1

if ! rg -q '\[SAME_SCAN_ACCESSOR\] before_getter_body=0' "$RUN_LOG"; then
  echo "same-scan union accessor regression: getter was already materialized" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

if ! rg -q '\[SAME_SCAN_ACCESSOR\] after_getter_body=1 second_scan_body=1' "$RUN_LOG"; then
  echo "same-scan union accessor regression: expected bodies were not materialized" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

if ! rg -q '\[MISSING_INCREMENTAL\] iter=0 .*raw_local_scan_invalidated=[1-9][0-9]* .*full_raw=2 .*full=2 .*match=1' "$RUN_LOG"; then
  echo "same-scan union accessor regression: first-scan occurrence evidence missing" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

if ! rg -q '\[MISSING_INCREMENTAL\] iter=1 .*raw_local_stable=[1-9][0-9]* .*raw_local_available_mismatch=[1-9][0-9]* .*raw_local_authority=full_scan raw_local_promotion=forbidden .*full_raw=2 .*full=0 .*match=1' "$RUN_LOG"; then
  echo "same-scan union accessor regression: raw/availability separation missing" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

if rg -q 'raw_local_false_reuse=[1-9][0-9]*' "$RUN_LOG"; then
  echo "same-scan union accessor regression: unexpected raw-local false reuse" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "missing_incremental_same_scan_union_accessor_ok"
