#!/usr/bin/env bash
# Compare standalone runtime printing against original Crystal with its standard prelude.
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/numeric-standalone-order.XXXXXX")"
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
puts "begin"
print 7_i32
puts 1.25_f32
print 2_i16
puts 3.5_f64
print 4_u8
puts ":u8"
print 5_u16
puts ":u16"
print 4000000000_u32
puts ":u32"
print 9000000000_i64
puts ":i64"
print 18000000000_u64
puts ":u64"
print true
puts ":bool"
puts "end"
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
      --no-prelude --no-ast-cache --no-llvm-cache --no-debug -o "$WORK/$stage.bin" \
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
printf 'PASS[numeric-standalone-order]: exact original-first mixed integer/float/string/bool print and puts order without candidate prelude\n'
