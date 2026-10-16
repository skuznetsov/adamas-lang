#!/usr/bin/env bash
# Preserve source admission for synthesized allocators and their specialized initializers.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
elif [[ -d "$ROOT_DIR/../crystal/src" ]]; then
  CRYSTAL_STDLIB="$(cd "$ROOT_DIR/../crystal/src" && pwd -P)"
else
  echo "set CRYSTAL_PATH to the external Crystal stdlib source directory" >&2
  exit 2
fi

[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "candidate, original Crystal, SAFE runner, or external stdlib is unavailable" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/materialized-allocator-source.XXXXXX")"
cleanup() {
  local status=$?
  for name in memory; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

# The scalar call first materializes a synthetic new/initialize pair. The union
# must retain that initializer's declaration even when its emitted name differs.
cat >"$WORK_DIR/memory.cr" <<'CRYSTAL'
IO::Memory.new("warm".to_slice)
def consume_memory(flag : Bool)
  content = flag ? "text" : "ab".to_slice
  IO::Memory.new(content).bytesize
end
puts consume_memory(true)
puts consume_memory(false)
puts IO::Memory.new("factory").bytesize
puts IO::Memory.new("slice".to_slice).bytesize
CRYSTAL
printf '4\n2\n7\n5\n' >"$WORK_DIR/memory.expected"

compile_and_run_positive() {
  local name="$1" compiler="$2" mode="$3" status=0
  local source="$WORK_DIR/$name.cr" output="$WORK_DIR/$mode-$name.bin"
  local log="$WORK_DIR/$mode-$name.compile.log"
  local cache="$WORK_DIR/$mode-$name.cache"
  if [[ "$mode" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$source" --no-debug \
      --link-flags=-fuse-ld=/usr/bin/ld -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$source" --no-ast-cache --no-llvm-cache \
      --no-debug -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$mode/$name]: compile exited $status" >&2
    tail -30 "$log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.run.resources" \
    "$SAFE_RUNNER" "$output" 10 512 >"$WORK_DIR/$mode-$name.stdout" \
    2>"$WORK_DIR/$mode-$name.run.log"; then
    echo "FAIL[$mode/$name]: runtime failed" >&2
    cat "$WORK_DIR/$mode-$name.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$mode-$name.run.log" || {
    cat "$WORK_DIR/$mode-$name.run.log" >&2
    return 1
  }
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$mode-$name.stdout"
}

compile_and_run_positive memory "$ORIGINAL_CRYSTAL_BIN" original
compile_and_run_positive memory "$COMPILER" candidate
echo 'PASS[memory]: original and candidate agree on union arms and scalar controls'
echo 'OPEN: first-demand allocator generation and rejection of unsupported Bool unions are separate existing gaps.'
