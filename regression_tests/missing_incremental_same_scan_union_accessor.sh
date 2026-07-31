#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT_DIR/regression_tests/missing_incremental_same_scan_union_accessor.cr"
TMP_DIR="$(mktemp -d /tmp/adamas_same_scan_union_accessor.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CRYSTAL_BIN="${CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
PROBE_BIN="$TMP_DIR/probe"
BUILD_LOG="$TMP_DIR/build.log"
DEMAND_FIRST_LOG="$TMP_DIR/demand_first.log"
MATERIALIZER_FIRST_LOG="$TMP_DIR/materializer_first.log"

CRYSTAL_CACHE_DIR="$TMP_DIR/cache" \
  "$ROOT_DIR/scripts/run_safe.sh" "$CRYSTAL_BIN" 180 6144 \
  build "$SOURCE" -o "$PROBE_BIN" --error-trace >"$BUILD_LOG" 2>&1
"$ROOT_DIR/scripts/run_safe.sh" "$PROBE_BIN" 30 2048 >"$DEMAND_FIRST_LOG" 2>&1
ADAMAS_SAME_SCAN_ORDER=materializer_first \
  "$ROOT_DIR/scripts/run_safe.sh" "$PROBE_BIN" 30 2048 \
  >"$MATERIALIZER_FIRST_LOG" 2>&1

if ! rg -q '\[SAME_SCAN_ACCESSOR\] order=demand_first before_getter_body=0' "$DEMAND_FIRST_LOG"; then
  echo "same-scan union accessor regression: getter was already materialized" >&2
  cat "$DEMAND_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[SAME_SCAN_ACCESSOR\] order=demand_first after_getter_body=1 second_scan_body=1' "$DEMAND_FIRST_LOG"; then
  echo "same-scan union accessor regression: expected bodies were not materialized" >&2
  cat "$DEMAND_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[SAME_SCAN_ACCESSOR\] order=demand_first canonical_getter=Outer::Info#kind canonical_union=Outer::Info#kind' "$DEMAND_FIRST_LOG"; then
  echo "same-scan union accessor regression: demand-first canonical names diverged" >&2
  cat "$DEMAND_FIRST_LOG" >&2
  exit 1
fi

if ! rg -Fq '[SAME_SCAN_ACCESSOR] order=demand_first precanonical=Outer::Info#kind -> Nil | Outer::Info#kind -> ' "$DEMAND_FIRST_LOG"; then
  echo "same-scan union accessor regression: demand-first raw occurrence order was not preserved" >&2
  cat "$DEMAND_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[MISSING_INCREMENTAL\] iter=0 .*raw_local_scan_invalidated=[1-9][0-9]* .*availability_replay_model_mismatch=[1-9][0-9]* .*full_raw=2 .*full=2 .*match=1' "$DEMAND_FIRST_LOG"; then
  echo "same-scan union accessor regression: first-scan occurrence evidence missing" >&2
  cat "$DEMAND_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[MISSING_INCREMENTAL\] iter=0 .*precanonical_indexed=3 .*precanonical_observed=3 .*precanonical_match=1 .*precanonical_authority=full_scan precanonical_promotion=forbidden' "$DEMAND_FIRST_LOG"; then
  echo "same-scan union accessor regression: demand-first pre-canonical occurrence index mismatch" >&2
  cat "$DEMAND_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[MISSING_INCREMENTAL\] iter=1 .*raw_local_stable=[1-9][0-9]* .*raw_local_available_mismatch=[1-9][0-9]* .*raw_local_authority=full_scan raw_local_promotion=forbidden .*full_raw=2 .*full=0 .*match=1' "$DEMAND_FIRST_LOG"; then
  echo "same-scan union accessor regression: raw/availability separation missing" >&2
  cat "$DEMAND_FIRST_LOG" >&2
  exit 1
fi

if rg -q 'raw_local_false_reuse=[1-9][0-9]*' "$DEMAND_FIRST_LOG"; then
  echo "same-scan union accessor regression: unexpected raw-local false reuse" >&2
  cat "$DEMAND_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[MISSING_INCREMENTAL_TERMINAL\] .*availability_replay_verdict=pre_scan_model_refuted .*verdict=inconclusive' "$DEMAND_FIRST_LOG"; then
  echo "same-scan union accessor regression: demand-first terminal did not fail closed" >&2
  cat "$DEMAND_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[SAME_SCAN_ACCESSOR\] order=materializer_first before_getter_body=0' "$MATERIALIZER_FIRST_LOG"; then
  echo "same-scan union accessor regression: reordered getter was already materialized" >&2
  cat "$MATERIALIZER_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[SAME_SCAN_ACCESSOR\] order=materializer_first after_getter_body=1 second_scan_body=1' "$MATERIALIZER_FIRST_LOG"; then
  echo "same-scan union accessor regression: reordered bodies were not materialized" >&2
  cat "$MATERIALIZER_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[SAME_SCAN_ACCESSOR\] order=materializer_first canonical_getter=Outer::Info#kind canonical_union=Outer::Info#kind' "$MATERIALIZER_FIRST_LOG"; then
  echo "same-scan union accessor regression: materializer-first canonical names diverged" >&2
  cat "$MATERIALIZER_FIRST_LOG" >&2
  exit 1
fi

if ! rg -Fq '[SAME_SCAN_ACCESSOR] order=materializer_first precanonical=Nil | Outer::Info#kind -> Outer::Info#kind -> ' "$MATERIALIZER_FIRST_LOG"; then
  echo "same-scan union accessor regression: materializer-first raw occurrence order was not preserved" >&2
  cat "$MATERIALIZER_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[MISSING_INCREMENTAL\] iter=0 .*availability_replay_model_mismatch=[1-9][0-9]* .*full_raw=2 .*full=1 .*match=1' "$MATERIALIZER_FIRST_LOG"; then
  echo "same-scan union accessor regression: reordered availability falsifier missing" >&2
  cat "$MATERIALIZER_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[MISSING_INCREMENTAL\] iter=0 .*precanonical_indexed=3 .*precanonical_observed=3 .*precanonical_match=1 .*precanonical_authority=full_scan precanonical_promotion=forbidden' "$MATERIALIZER_FIRST_LOG"; then
  echo "same-scan union accessor regression: materializer-first pre-canonical occurrence index mismatch" >&2
  cat "$MATERIALIZER_FIRST_LOG" >&2
  exit 1
fi

if ! rg -q '\[MISSING_INCREMENTAL_TERMINAL\] .*availability_replay_verdict=pre_scan_model_refuted .*verdict=inconclusive' "$MATERIALIZER_FIRST_LOG"; then
  echo "same-scan union accessor regression: materializer-first terminal did not fail closed" >&2
  cat "$MATERIALIZER_FIRST_LOG" >&2
  exit 1
fi

echo "missing_incremental_same_scan_union_accessor_ok"
