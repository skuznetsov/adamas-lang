#!/usr/bin/env bash
# Original-first parity for signed-number token boundaries and their AST consumers.
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/signed-literal-boundary.XXXXXX")"
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
# Existing direct AST observations: these expression-position signs are parsed
# differently from a sign fused into a numeric token by Crystal's lexer.
puts typeof(-2_147_483_648).name
puts typeof(-2_147_483_649).name
puts typeof(+2_147_483_648).name
puts typeof(-9_223_372_036_854_775_808).name
puts typeof(-1.5_f32).name
puts typeof(- -2_147_483_648).name
puts typeof(+ -2_147_483_648).name

# Generic type-position typeof uses the textual resolver. It must keep the
# same token adjacency and nested-unary semantics as expression-position typeof.
puts Pointer(typeof(-2_147_483_648)).name
puts Pointer(typeof(- 2_147_483_648)).name
puts Pointer(typeof(- -2_147_483_648)).name
puts Pointer(typeof(+ -2_147_483_648)).name
puts Pointer(typeof(+ - 2_147_483_648)).name
puts Pointer(typeof(- # preserve the separated sign in a type argument too
  2_147_483_648)).name

# Spacing, a comment, and a newline must keep the operator separate from the
# number even though trivia is omitted from the parser's token stream.
puts typeof(- 2_147_483_648).name
puts typeof(- # the source span now has a gap
  2_147_483_648).name
puts typeof(- - 2_147_483_648).name

# Ordinary inferred locals must observe the same signed minimum kinds.
local_i32_min = -2_147_483_648
local_i64_min = -9_223_372_036_854_775_808
puts typeof(local_i32_min).name
puts typeof(local_i64_min).name

# A fused sign belongs to the literal before postfix method chaining.
puts -2.to_s
puts (-2).to_s

# Subtraction tokenization must remain intact for all whitespace placements;
# a negative literal on the right also exercises unary parsing after an op.
puts (5-2).to_s
puts (5 -2).to_s
puts (5- 2).to_s
puts (5 - 2).to_s
puts (1 - -2).to_s
puts -2.abs

# Signed source parsing must also preserve based literal values and suffixes.
hex_i32_min = -0x8000_0000
hex_i64_min = -0x8000_0000_0000_0000
puts typeof(hex_i32_min).name
puts hex_i32_min
puts typeof(hex_i64_min).name
puts hex_i64_min
puts typeof(-0b1000_0000_0000_0000_0000_0000_0000_0000).name
puts typeof(-2_i8).name
puts -2_i8
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
printf 'PASS[signed-literal-boundary]: exact original-first output parity for adjacent/spaced/nested signs, locals, postfix calls, and subtraction forms\n'
