#!/usr/bin/env bash
# Skip provably disjoint builtin case bodies for container unions; retain reachable bodies.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/builtin-container-case.XXXXXX")"
cleanup() {
  local status=$?
  for name in containers; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/containers.cr" <<'CRYSTAL'
def byte_only(value : UInt8)
  7
end

def classify_container(value)
  case value
  when UInt8
    byte_only(value)
  when Int64
    11
  when Array
    21
  when Hash
    22
  when Tuple
    23
  when NamedTuple
    24
  else
    0
  end
end

def drive_array(flag : Bool)
  classify_container(flag ? 17_i64 : [1])
end

def drive_hash(flag : Bool)
  classify_container(flag ? 17_i64 : {"a" => 1})
end

def drive_tuple(flag : Bool)
  classify_container(flag ? 17_i64 : {1, 2})
end

def drive_named_tuple(flag : Bool)
  classify_container(flag ? 17_i64 : {a: 1})
end

def drive_matching_byte(flag : Bool)
  classify_container(flag ? 9_u8 : [1])
end

puts drive_array(true)
puts drive_array(false)
puts drive_hash(true)
puts drive_hash(false)
puts drive_tuple(true)
puts drive_tuple(false)
puts drive_named_tuple(true)
puts drive_named_tuple(false)
puts drive_matching_byte(true)
puts drive_matching_byte(false)
CRYSTAL
printf '11\n21\n11\n22\n11\n23\n11\n24\n7\n21\n' >"$WORK_DIR/containers.expected"

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

compile_and_run_positive containers "$ORIGINAL_CRYSTAL_BIN" original
compile_and_run_positive containers "$COMPILER" candidate
echo 'PASS[containers]: ten Array, Hash, Tuple, NamedTuple and reachable UInt8 outputs agree'
