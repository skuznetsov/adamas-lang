#!/usr/bin/env bash
# Durable shape/representation regression for Tuple#to_static_array.
#
# The expected values are first checked against the original Crystal compiler,
# then against Adamas.  Keep every executable behind run_safe.sh: this probe
# intentionally exercises tuple/static-array ABI boundaries.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORACLE="${CRYSTAL_ORACLE:-crystal}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tuple_static_shape.XXXXXX")"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

extract_stdout() {
  awk '
    /^=== STDOUT ===$/ { in_stdout=1; next }
    /^=== STDERR ===$/ { in_stdout=0; next }
    in_stdout && $0 !~ /^\[EXIT:/ { print }
  ' "$1" | tr -d '\r\n'
}

run_binary() {
  local binary="$1"
  local output="$2"
  "$RUN_SAFE" "$binary" 5 512 >"$output"
  extract_stdout "$output"
}

run_compiler() {
  local compiler="$1"
  local output="$2"
  shift 2
  if ! "$RUN_SAFE" "$compiler" 120 2048 "$@" >"$output" 2>&1; then
    tail -n 80 "$output" >&2
    return 1
  fi
}

SRC="$TMP_DIR/shape.cr"
ORACLE_BIN="$TMP_DIR/shape.oracle"
ADAMAS_BIN="$TMP_DIR/shape.adamas"
ORACLE_RUN="$TMP_DIR/shape.oracle.run"
ADAMAS_RUN="$TMP_DIR/shape.adamas.run"
ORACLE_BUILD="$TMP_DIR/shape.oracle.build"
ADAMAS_BUILD="$TMP_DIR/shape.adamas.build"
EXPECTED="h=2:97:98;u=3:true:true:true;e=0;n=2:1:98:2:99"

printf '%s\n' \
  $'homogeneous = {\'a\', \'b\'}.to_static_array.to_slice\n' \
  $'heterogeneous = {1, \'a\', true}.to_static_array.to_slice\n' \
  $'empty = Tuple.new.to_static_array.to_slice\n' \
  $'nested = { {1, \'b\'}, {2, \'c\'} }.to_static_array.to_slice\n' \
  $'puts "h=#{homogeneous.size}:#{homogeneous[0].ord}:#{homogeneous[1].ord};u=#{heterogeneous.size}:#{heterogeneous[0].is_a?(Int32)}:#{heterogeneous[1].is_a?(Char)}:#{heterogeneous[2].is_a?(Bool)};e=#{empty.size};n=#{nested.size}:#{nested[0][0]}:#{nested[0][1].ord}:#{nested[1][0]}:#{nested[1][1].ord}"' \
  >"$SRC"

CRYSTAL_CACHE_DIR="$TMP_DIR/crystal-cache" run_compiler \
  "$ORACLE" "$ORACLE_BUILD" build "$SRC" -o "$ORACLE_BIN"
ORACLE_ACTUAL="$(run_binary "$ORACLE_BIN" "$ORACLE_RUN")"
if [[ "$ORACLE_ACTUAL" != "$EXPECTED" ]]; then
  echo "tuple_to_static_array_shape_oracle_failed: expected '$EXPECTED', got '$ORACLE_ACTUAL'" >&2
  exit 1
fi

run_compiler "$COMPILER" "$ADAMAS_BUILD" "$SRC" -o "$ADAMAS_BIN"
ADAMAS_ACTUAL="$(run_binary "$ADAMAS_BIN" "$ADAMAS_RUN")"
if [[ "$ADAMAS_ACTUAL" != "$EXPECTED" ]]; then
  echo "tuple_to_static_array_shape_repro_red: expected '$EXPECTED', got '$ADAMAS_ACTUAL'" >&2
  exit 1
fi
echo "tuple_to_static_array_shape_repro_ok"
