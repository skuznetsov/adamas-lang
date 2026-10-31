#!/usr/bin/env bash
# Pointer(T)#value= assignment preserves the declared pointee representation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pointer-value-store.XXXXXX")"

cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$SAFE_RUNNER" || ! -x "$ORIGINAL_CRYSTAL_BIN" || ! -f "$CRYSTAL_STDLIB/empty.cr" ]]; then
  echo "ERROR: safe runner, stock Crystal, or stock Crystal stdlib is unavailable" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" != 0 && "$ORIGINAL_ONLY" != 1 ]]; then
  echo "ERROR: ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" != 1 && ! -x "$ADAMAS_BIN" ]]; then
  echo "ERROR: candidate Adamas compiler is unavailable: $ADAMAS_BIN" >&2
  exit 2
fi

cat >"$WORK_DIR/nullable.cr" <<'CRYSTAL'
@[Link("c")]
lib PointerValueStoreNative
  fun malloc(size : UInt64) : Void*
  fun free(address : Void*) : Void
  fun putchar(value : Int32) : Int32
end

def read_nullable(pointer : Pointer(Int32?)) : Int32?
  pointer.value
end

nullable_memory = PointerValueStoreNative.malloc(16_u64)
nullable = Pointer(Int32?).new(nullable_memory.address)
nullable.value = nil
nullable.value = 65
if value = read_nullable(nullable)
  PointerValueStoreNative.putchar(value)
else
  PointerValueStoreNative.putchar(90)
end
nullable.value = nil
if read_nullable(nullable)
  PointerValueStoreNative.putchar(90)
else
  PointerValueStoreNative.putchar(66)
end

byte_memory = PointerValueStoreNative.malloc(1_u64)
byte = Pointer(UInt8).new(byte_memory.address)
byte.value = 67
PointerValueStoreNative.putchar(byte.value.to_i32)

signed_memory = PointerValueStoreNative.malloc(1_u64)
signed = Pointer(Int8).new(signed_memory.address)
signed.value = -1
signed_code = if signed.value == -1_i8
                68
              else
                90
              end
PointerValueStoreNative.putchar(signed_code)

float_memory = PointerValueStoreNative.malloc(4_u64)
float = Pointer(Float32).new(float_memory.address)
float.value = 1.0
float_code = if float.value == 1.0_f32
               69
             else
               90
             end
PointerValueStoreNative.putchar(float_code)
PointerValueStoreNative.putchar(10)
PointerValueStoreNative.free(nullable_memory)
PointerValueStoreNative.free(byte_memory)
PointerValueStoreNative.free(signed_memory)
PointerValueStoreNative.free(float_memory)
CRYSTAL

cat >"$WORK_DIR/wrong_type.cr" <<'CRYSTAL'
pointer = Pointer(Int32?).new(0_u64)
pointer.value = "wrong"
CRYSTAL

cat >"$WORK_DIR/out_of_range.cr" <<'CRYSTAL'
pointer = Pointer(UInt8).new(0_u64)
pointer.value = 256
CRYSTAL

compile_stock() {
  local name="$1"
  local status=0
  CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/stock-cache-$name" \
    "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 120 4096 \
    build --prelude=empty --no-debug "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/stock-$name.bin" "--link-flags=$LINK_FLAGS" \
    >"$WORK_DIR/stock-$name.build.log" 2>&1 || status=$?
  printf '%s\n' "$status"
}

compile_candidate() {
  local mode="$1" name="$2"
  local status=0
  local -a mode_env
  if [[ "$mode" == eager ]]; then
    mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  fi
  CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/cache-$mode-$name" \
    ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS" \
    "${mode_env[@]}" "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 \
    "$WORK_DIR/$name.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
    -o "$WORK_DIR/candidate-$mode-$name.bin" \
    >"$WORK_DIR/candidate-$mode-$name.build.log" 2>&1 || status=$?
  printf '%s\n' "$status"
}

stock_status="$(compile_stock nullable)"
if [[ "$stock_status" != 0 ]]; then
  cat "$WORK_DIR/stock-nullable.build.log" >&2
  echo "FAIL stock nullable compile" >&2
  exit 1
fi
RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/stock-nullable.bin" 5 512 \
  >"$WORK_DIR/stock-nullable.stdout" 2>"$WORK_DIR/stock-nullable.run.log"
printf 'ABCDE\n' >"$WORK_DIR/expected.stdout"
if ! diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/stock-nullable.stdout"; then
  echo "FAIL stock nullable output" >&2
  exit 1
fi

for negative in wrong_type out_of_range; do
  stock_status="$(compile_stock "$negative")"
  if [[ "$stock_status" == 0 ]]; then
    printf 'FAIL stock accepted %s\n' "$negative" >&2
    exit 1
  fi
done

if [[ "$ORIGINAL_ONLY" == 1 ]]; then
  printf 'PASS: stock pointer value store oracle (nullable, literals, strict negatives)\n'
  exit 0
fi

for mode in lazy eager; do
  candidate_status="$(compile_candidate "$mode" nullable)"
  if [[ "$candidate_status" != 0 ]]; then
    cat "$WORK_DIR/candidate-$mode-nullable.build.log" >&2
    printf 'FAIL candidate-%s nullable compile\n' "$mode" >&2
    exit 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/candidate-$mode-nullable.bin" 5 512 \
    >"$WORK_DIR/candidate-$mode-nullable.stdout" 2>"$WORK_DIR/candidate-$mode-nullable.run.log"
  if ! diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/candidate-$mode-nullable.stdout"; then
    printf 'FAIL candidate-%s nullable output\n' "$mode" >&2
    exit 1
  fi

  for negative in wrong_type out_of_range; do
    candidate_status="$(compile_candidate "$mode" "$negative")"
    if [[ "$candidate_status" == 0 ]]; then
      printf 'FAIL candidate-%s accepted %s\n' "$mode" "$negative" >&2
      exit 1
    fi
  done
done

printf 'PASS: pointer value store representation and source checks (stock, lazy, eager)\n'
