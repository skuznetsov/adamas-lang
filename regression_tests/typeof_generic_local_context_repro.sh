#!/usr/bin/env bash
# Type-position typeof must see the same lexical locals as expression typeof.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
if [[ -z "${CRYSTAL_PATH:-}" && -d "$ROOT_DIR/../crystal/src" ]]; then
  export CRYSTAL_PATH="$ROOT_DIR/../crystal/src"
fi
[[ -x "$SAFE" && -x "$COMPILER" && -x "$ORIGINAL" ]] || exit 2
WORK="$(mktemp -d "${TMPDIR:-/tmp}/typeof-generic-local.XXXXXX")"
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
cat >"$WORK/local_context.cr" <<'CRYSTAL'
local_value = "local-value"
phase = "phase"
cacheE = "cacheE"
file = "file"
unit = "unit"
float_name = "float-name"
f = "f"
u = "u"
i = "i"
CRYSTAL
for name in local_value phase cacheE file unit float_name f u i; do
  printf 'puts typeof(%s).name\nslice_%s = Slice[%s]\nputs typeof(slice_%s).name\nputs slice_%s[0]\n' \
    "$name" "$name" "$name" "$name" "$name" >>"$WORK/local_context.cr"
done
cat >>"$WORK/local_context.cr" <<'CRYSTAL'
def method_context(value : String)
  local_value = value
  pointer = Pointer(typeof(local_value)).null
  puts typeof(pointer).name
  values = Slice[local_value]
  puts typeof(values).name
  puts values[0]
end
method_context("method-value")

# Mutation makes this an owner-bound capture; typeof must use its payload type.
captured_value = "before"
1.times do
  captured_value = "captured-value"
  pointer = Pointer(typeof(captured_value)).null
  puts typeof(pointer).name
  values = Slice[captured_value]
  puts typeof(values).name
  puts values[0]
end
# Leaving the inlined block must restore the surrounding typeof scope.
pointer = Pointer(typeof(unit)).null
puts typeof(pointer).name
puts captured_value

# Reuse the same source expression under different method specializations.
# A temporary typeof environment must not leak its cache entries to a sibling.
def sibling_context(value)
  pointer = Pointer(typeof(value)).null
  puts typeof(pointer).name
  values = Slice[value]
  puts typeof(values).name
  puts values[0]
end
sibling_context(7_i32)
sibling_context(11_i64)
sibling_context(true)
sibling_context("sibling-value")

# Static [] has its own generic receiver path, separate from ordinary calls.
struct TypeofIndex(T)
  def self.[](value : T) : T
    value
  end
end
puts TypeofIndex(typeof(local_value))[local_value]
CRYSTAL
for value in local-value phase cacheE file unit float-name f u i; do
  printf 'String\nSlice(String)\n%s\n' "$value"
done >"$WORK/expected.stdout"
cat >>"$WORK/expected.stdout" <<'EXPECTED'
Pointer(String)
Slice(String)
method-value
Pointer(String)
Slice(String)
captured-value
Pointer(String)
captured-value
Pointer(Int32)
Slice(Int32)
7
Pointer(Int64)
Slice(Int64)
11
Pointer(Bool)
Slice(Bool)
true
Pointer(String)
Slice(String)
sibling-value
local-value
EXPECTED
for stage in original candidate; do
  if [[ "$stage" == original ]]; then
    args=(build "$WORK/local_context.cr" --no-debug -o "$WORK/$stage.bin")
    [[ "$(uname -s)" != Darwin ]] || args+=(--link-flags=-fuse-ld=/usr/bin/ld)
    if ! CRYSTAL_CACHE_DIR="$WORK/original.cache" "$SAFE" "$ORIGINAL" 180 8192 \
      "${args[@]}" >"$WORK/$stage.compile.log" 2>&1; then
      tail -40 "$WORK/$stage.compile.log" >&2
      exit 1
    fi
  else
    if ! CRYSTAL_CACHE_DIR="$WORK/candidate.cache" ADAMAS_LLVM_CACHE=0 \
      "$SAFE" "$COMPILER" 180 8192 "$WORK/local_context.cr" --no-ast-cache \
      --no-llvm-cache --no-debug -o "$WORK/$stage.bin" >"$WORK/$stage.compile.log" 2>&1; then
      tail -40 "$WORK/$stage.compile.log" >&2
      exit 1
    fi
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/$stage.bin" 15 1024 \
    >"$WORK/$stage.stdout" 2>"$WORK/$stage.run.log"
  cmp "$WORK/expected.stdout" "$WORK/$stage.stdout"
  if grep -Fq '=== STDERR ===' "$WORK/$stage.run.log"; then
    cat "$WORK/$stage.run.log" >&2
    exit 1
  fi
done
cmp "$WORK/original.stdout" "$WORK/candidate.stdout"
printf 'PASS[typeof-generic-local-context]: exact stdout for locals, method scope and capture payload\n'
