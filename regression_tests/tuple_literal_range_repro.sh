#!/usr/bin/env bash
# Tuple literal range slices preserve concrete fields and the source rejection
# for runtime/non-Int32 ranges. Every generated binary uses the safe runner.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
if [[ -z "$COMPILER" || ! -x "$COMPILER" || ! -x "$ORIGINAL_CRYSTAL_BIN" ]]; then
  echo "ERROR: usage: $0 <candidate-compiler>; original Crystal must be available" >&2
  exit 2
fi
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tuple-literal-range.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_work=$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib TupleRangeProbeOutput
  fun exit(status : Int32) : NoReturn
  fun putchar(value : Int32) : Int32
end
def tuple_range_values
  TupleRangeProbeOutput.putchar(65)
  {21, 0x1_0000_0016_i64, true}
end
def tuple_range_empty_marker(value : Tuple()) : Int32
  42
end
selected = tuple_range_values[0..1]
TupleRangeProbeOutput.exit(81) unless selected[0] == 21
TupleRangeProbeOutput.exit(82) unless selected[1] == 0x1_0000_0016_i64
values = {21, 0x1_0000_0016_i64, true}
negative = values[-2..-1]
TupleRangeProbeOutput.exit(83) unless negative[0] == 0x1_0000_0016_i64 && negative[1]
exclusive = values[0...2]
TupleRangeProbeOutput.exit(84) unless exclusive[0] == 21 && exclusive[1] == 0x1_0000_0016_i64
beginless = values[..1]
TupleRangeProbeOutput.exit(85) unless beginless[1] == 0x1_0000_0016_i64
endless = values[2..]
TupleRangeProbeOutput.exit(86) unless endless[0]
clamped = values[1..99]
TupleRangeProbeOutput.exit(87) unless clamped[0] == 0x1_0000_0016_i64 && clamped[1]
TupleRangeProbeOutput.exit(88) unless tuple_range_empty_marker(values[3..3]) == 42
TupleRangeProbeOutput.exit(89) unless tuple_range_empty_marker(values[0...0]) == 42
TupleRangeProbeOutput.putchar(42)
TupleRangeProbeOutput.putchar(10)
CRYSTAL

build() {
  local kind="$1" source="$2" output="$3"
  if [[ "$kind" == "original" ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$source" -o "$output" \
      --link-flags=-fuse-ld=/usr/bin/ld
  else
    local flags=(--no-ast-cache --no-llvm-cache)
    # Keep the positive lowering oracle independent of stdlib initialization.
    # Rejection controls below load the original Tuple source definitions.
    if [[ "$source" == "$WORK_DIR/probe.cr" && "${ADAMAS_TUPLE_RANGE_FULL_PRELUDE:-0}" != "1" ]]; then
      flags+=(--no-prelude)
    fi
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$source" "${flags[@]}" -o "$output"
  fi
}

run() {
  local kind="$1"
  local status=0
  "$SAFE_RUNNER" "$WORK_DIR/$kind.bin" 10 512 >"$WORK_DIR/$kind.run.log" 2>&1 || status=$?
  if [[ "$status" -ne 0 ]]; then
    cat "$WORK_DIR/$kind.run.log" >&2
    return 1
  fi
  sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/{/^=== STDOUT ===$/d;/^=== STDERR ===$/d;p;}' \
    "$WORK_DIR/$kind.run.log" >"$WORK_DIR/$kind.stdout"
}

for kind in original candidate; do
  if ! build "$kind" "$WORK_DIR/probe.cr" "$WORK_DIR/$kind.bin" >"$WORK_DIR/$kind.build.log" 2>&1; then
    cat "$WORK_DIR/$kind.build.log" >&2
    exit 1
  fi
  run "$kind"
done
printf 'A*\n' >"$WORK_DIR/expected.stdout"
diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/original.stdout"
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"

for guard in runtime wide start; do
  case "$guard" in
    runtime)
      printf 'values = {1, 2_i64, true}\nrange = 0..1\nvalues[range]\n' >"$WORK_DIR/reject.cr"
      expected='can only be called with range literals known at compile-time'
      ;;
    wide)
      printf 'values = {1, 2_i64, true}\nvalues[0_i64..1]\n' >"$WORK_DIR/reject.cr"
      expected='can only be called with range literals known at compile-time'
      ;;
    start)
      printf 'values = {1, 2_i64, true}\nvalues[4..5]\n' >"$WORK_DIR/reject.cr"
      expected='begin index out of bounds'
      ;;
  esac
  for kind in original candidate; do
    log="$WORK_DIR/$kind.$guard.log"
    if build "$kind" "$WORK_DIR/reject.cr" "$WORK_DIR/$kind.$guard.bin" >"$log" 2>&1; then
      echo "FAIL: $kind accepted $guard Tuple range" >&2
      exit 1
    fi
    if ! grep -Fq "$expected" "$log"; then
      echo "FAIL: $kind rejected $guard for an unrelated reason" >&2
      cat "$log" >&2
      exit 1
    fi
  done
done
echo "PASS: Tuple literal ranges match Crystal and preserve range rejection guards"
