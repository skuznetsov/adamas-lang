#!/usr/bin/env bash
# Original-first parity checks for numeric typeof classification and local projections.
set -euo pipefail

find_root() {
  local dir="$PWD"
  while [[ "$dir" != / ]]; do
    if [[ -x "$dir/scripts/run_safe.sh" ]]; then printf '%s\n' "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [[ "$dir" != / ]]; do
    if [[ -x "$dir/scripts/run_safe.sh" ]]; then printf '%s\n' "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  return 1
}
ROOT_DIR="${ADAMAS_ROOT:-$(find_root || true)}"
if [[ -z "$ROOT_DIR" ]]; then
  echo "could not find Adamas root; set ADAMAS_ROOT" >&2
  exit 2
fi
SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
if [[ -z "${CRYSTAL_PATH:-}" && -d "$ROOT_DIR/../crystal/src" ]]; then
  export CRYSTAL_PATH="$ROOT_DIR/../crystal/src"
fi
[[ -x "$SAFE" && -x "$COMPILER" ]] || {
  echo "missing safe runner or candidate compiler" >&2
  exit 2
}
command -v "$ORIGINAL" >/dev/null 2>&1 || [[ -x "$ORIGINAL" ]] || {
  echo "missing original Crystal compiler: $ORIGINAL" >&2
  exit 2
}
WORK="$(mktemp -d "${TMPDIR:-/tmp}/numeric2388-signed.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK/original.cache" "$WORK/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

cat >"$WORK/core.cr" <<'CRYSTAL'
# Existing literal, decimal-chain, and local-index coverage from the projection regression.
puts Pointer(typeof(+1)).name
puts Pointer(typeof(-1)).name
puts Pointer(typeof(0xFE)).name
puts Pointer(typeof(0xDEAD)).name
puts Pointer(typeof(0b101)).name
puts Pointer(typeof(0o77)).name
puts Pointer(typeof(1e+3)).name
puts Pointer(typeof(2_147_483_647)).name
puts Pointer(typeof(2_147_483_648)).name
puts Pointer(typeof(1_i8)).name
puts Pointer(typeof(1_i16)).name
puts Pointer(typeof(1_i32)).name
puts Pointer(typeof(1_i64)).name
puts Pointer(typeof(1_i128)).name
puts Pointer(typeof(1_u8)).name
puts Pointer(typeof(1_u16)).name
puts Pointer(typeof(1_u32)).name
puts Pointer(typeof(1_u64)).name
puts Pointer(typeof(1_u128)).name
puts Pointer(typeof(1_f32)).name
puts Pointer(typeof(1_f64)).name
puts Pointer(typeof(1.5_f32)).name
puts Pointer(typeof(1.5_f32.to_s)).name
puts Pointer(typeof(1.5_f32.abs)).name
puts Pointer(typeof(1.5e-2.abs)).name
puts Pointer(typeof(1e-2.abs)).name
local_float = 2.5_f32
puts Pointer(typeof(local_float.to_s)).name
puts Pointer(typeof(local_float.abs)).name
tuple_value = {1.5_f32, 2.0}
puts Pointer(typeof(tuple_value[0])).name
puts Pointer(typeof(tuple_value[1])).name
array_value = [1.5_f32]
puts Pointer(typeof(array_value[0])).name
CRYSTAL
cat >"$WORK/core.expected" <<'EXPECTED'
Pointer(Int32)
Pointer(Int32)
Pointer(Int32)
Pointer(Int32)
Pointer(Int32)
Pointer(Int32)
Pointer(Float64)
Pointer(Int32)
Pointer(Int64)
Pointer(Int8)
Pointer(Int16)
Pointer(Int32)
Pointer(Int64)
Pointer(Int128)
Pointer(UInt8)
Pointer(UInt16)
Pointer(UInt32)
Pointer(UInt64)
Pointer(UInt128)
Pointer(Float32)
Pointer(Float64)
Pointer(Float32)
Pointer(String)
Pointer(Float32)
Pointer(Float64)
Pointer(Float64)
Pointer(String)
Pointer(Float32)
Pointer(Float32)
Pointer(Float64)
Pointer(Float32)
EXPECTED

cat >"$WORK/signed_literal_local_box.cr" <<'CRYSTAL'
class Box(T)
end

# These values probe source unary sign handling at both signed boundaries.
puts Pointer(typeof(-2_147_483_648)).name
puts Pointer(typeof(-2_147_483_649)).name
puts Pointer(typeof(+2_147_483_648)).name
puts Pointer(typeof(-9_223_372_036_854_775_808)).name
puts Pointer(typeof(-1.5_f32)).name

# Explicit suffix minima must keep the annotated kind under unary minus.
puts Pointer(typeof(-128_i8)).name
puts Pointer(typeof(-32_768_i16)).name
puts Pointer(typeof(-2_147_483_648_i32)).name
puts Pointer(typeof(-9_223_372_036_854_775_808_i64)).name

# The same signed literals through ordinary local inference and typeof(local).
local_i32_min = -2_147_483_648
local_i32_below_min = -2_147_483_649
local_i64_min = -9_223_372_036_854_775_808
local_f32_negative = -1.5_f32
puts Pointer(typeof(local_i32_min)).name
puts Pointer(typeof(local_i32_below_min)).name
puts Pointer(typeof(local_i64_min)).name
puts Pointer(typeof(local_f32_negative)).name

# Generic type arguments are included only as original-valid type contexts.
puts Box(typeof(-2_147_483_648)).name
puts Box(typeof(-2_147_483_649)).name
puts Box(typeof(-9_223_372_036_854_775_808_i64)).name
CRYSTAL

cat >"$WORK/hex_signs.cr" <<'CRYSTAL'
# Unsuffixed signs exercise magnitude classification independently of suffixes.
puts Pointer(typeof(+0x7fff_ffff)).name
puts Pointer(typeof(-0x8000_0000)).name
puts Pointer(typeof(+0x8000_0000)).name
puts Pointer(typeof(-0x8000_0001)).name
puts Pointer(typeof(-0x8000_0000_0000_0000)).name

# Explicit signed minima are guards that sign handling does not override suffixes.
puts Pointer(typeof(-0x80_i8)).name
puts Pointer(typeof(-0x8000_i16)).name
puts Pointer(typeof(-0x8000_0000_i32)).name
puts Pointer(typeof(-0x8000_0000_0000_0000_i64)).name

hex_i32_min = -0x8000_0000
hex_i32_below_min = -0x8000_0001
hex_i64_min = -0x8000_0000_0000_0000
puts Pointer(typeof(hex_i32_min)).name
puts Pointer(typeof(hex_i32_below_min)).name
puts Pointer(typeof(hex_i64_min)).name
CRYSTAL

compile() {
  local stage="$1" source="$2"
  if [[ "$stage" == original ]]; then
    local args=(build "$source" --no-debug -o "$WORK/$stage.bin")
    [[ "$(uname -s)" != Darwin ]] || args+=(--link-flags=-fuse-ld=/usr/bin/ld)
    CRYSTAL_CACHE_DIR="$WORK/original.cache" "$SAFE" "$ORIGINAL" 180 8192 \
      "${args[@]}" >"$WORK/$stage.compile.log" 2>&1
  else
    CRYSTAL_CACHE_DIR="$WORK/candidate.cache" ADAMAS_LLVM_CACHE=0 \
      "$SAFE" "$COMPILER" 180 8192 "$source" --no-ast-cache \
      --no-llvm-cache --no-debug -o "$WORK/$stage.bin" \
      >"$WORK/$stage.compile.log" 2>&1
  fi
}
run_stage() {
  local stage="$1" source="$2"
  if ! compile "$stage" "$source"; then
    tail -60 "$WORK/$stage.compile.log" >&2
    return 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/$stage.bin" 15 1024 \
    >"$WORK/$stage.stdout" 2>"$WORK/$stage.run.log"
  if grep -Fq '=== STDERR ===' "$WORK/$stage.run.log"; then
    cat "$WORK/$stage.run.log" >&2
    return 1
  fi
}
compare_case() {
  local name="$1" source="$2" expected="${3:-}"
  run_stage original "$source"
  if [[ -n "$expected" ]]; then cmp "$expected" "$WORK/original.stdout"; fi
  run_stage candidate "$source"
  cmp "$WORK/original.stdout" "$WORK/candidate.stdout"
  [[ -z "$expected" ]] || cmp "$expected" "$WORK/candidate.stdout"
  cp "$WORK/original.stdout" "$WORK/$name.original.stdout"
  cp "$WORK/candidate.stdout" "$WORK/$name.candidate.stdout"
}

# Original is compiled/run first for each source; legacy cases retain static bytes.
compare_case core "$WORK/core.cr" "$WORK/core.expected"
compare_case signed_literal_local_box "$WORK/signed_literal_local_box.cr"
compare_case hex_signs "$WORK/hex_signs.cr"

printf 'PASS[numeric2388]: exact legacy output plus original-first signed, suffix-minimum, hexadecimal-sign, local-type, and Box(typeof(...)) parity\n'
