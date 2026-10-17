#!/usr/bin/env bash
# Original-first byte parity for literal and inferred numeric printing through Crystal IO.
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/numeric-io-order.XXXXXX")"
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

cat >"$WORK/signed_literal_boundary.cr" <<'CRYSTAL'
STDOUT.print "before_literals:"
puts -2_i8
puts 3_i16
puts 4
puts 5_i64
puts 6_u8
puts 7_u16
puts 8_u32
puts 9_u64
puts 1.25_f32
puts 2.5_f64
STDOUT.print "between_values:"
value_i8 = -3_i8
value_f32 = 3.25_f32
value_f64 = 4.5_f64
puts value_i8
puts value_f32
puts value_f64
print 10_i8
STDOUT.print "/"
print 11_u16
STDOUT.print "/"
print 1.5_f32
STDOUT.print "/"
puts 2.25_f64
STDOUT.sync = true
STDOUT.print "synced:"
puts 12_i16
STDOUT.sync = false
STDOUT.print "after_sync:"
puts 13_u8
memory = IO::Memory.new
memory.print(6_i8)
memory.print("/")
memory.puts(2.5_f32)
STDOUT.print memory.to_s
STDOUT.puts "after_literals"
CRYSTAL

compile() {
  local stage="$1"
  if [[ "$stage" == original ]]; then
    local args=(build "$WORK/signed_literal_boundary.cr" --no-debug -o "$WORK/$stage.bin")
    [[ "$(uname -s)" != Darwin ]] || args+=(--link-flags=-fuse-ld=/usr/bin/ld)
    CRYSTAL_CACHE_DIR="$WORK/original.cache" "$SAFE" "$ORIGINAL" 180 8192 \
      "${args[@]}" >"$WORK/$stage.compile.log" 2>&1
  else
    CRYSTAL_CACHE_DIR="$WORK/candidate.cache" ADAMAS_LLVM_CACHE=0 \
      "$SAFE" "$COMPILER" 180 8192 "$WORK/signed_literal_boundary.cr" \
      --no-ast-cache --no-llvm-cache --no-debug -o "$WORK/$stage.bin" \
      >"$WORK/$stage.compile.log" 2>&1
  fi
}

run_stage() {
  local stage="$1"
  if ! compile "$stage"; then
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

# The original compiler is deliberately compiled and run before the candidate.
run_stage original
run_stage candidate
cmp "$WORK/original.stdout" "$WORK/candidate.stdout"
printf 'PASS[numeric-io-order]: exact original-first literal/local puts and print ordering, sync transitions, and memory output\n'
