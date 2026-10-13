#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
if [[ $# -gt 1 || ! -x "$COMPILER" ]]; then
  echo "usage: $0 [compiler]" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/included_method_forall_shadow.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/hir"
HIR="$OUT.hir"
BIN="$TMP_DIR/runtime"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"

cat >"$SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Flow(T)
  def carry(
    obj : U,
    label : String = "default contains forall U",
    & : T, U ->
  ) forall U
    each do |item|
      yield item, obj
    end
    obj
  end

  def carry_annotated(
    obj : U,
    label : String = "default contains forall U",
    & : T, U ->
  ) : U forall U
    each do |item|
      yield item, obj
    end
    obj
  end

  def carry_twice(
    left : U,
    right : U,
    label : String = "repeated forall U",
    & : T, U, U ->
  ) forall U
    each do |item|
      yield item, left, right
    end
    left
  end
end

class GenericFlow(U)
  include Flow(String)

  def each
    yield "x"
  end
end

module OtherFlow(T)
  def carry(
    obj : U,
    label : String = "other default contains forall U",
    & : T, U ->
  ) forall U
    each do |item|
      yield item, obj
    end
    obj
  end
end

class OtherGenericFlow(U)
  include OtherFlow(Int64)

  def each
    yield 9_i64
  end
end

class DirectShadowFlow(U)
  include Flow(String)

  def each
    yield "shadow"
  end

  def carry(obj : U, & : U ->) : U
    yield obj
    obj
  end
end

module ReceiverFlow(U)
  def carry_receiver(obj : U, & : U ->)
    yield obj
    obj
  end
end

class ReceiverBox(U)
  include ReceiverFlow(U)
end

def item_tag(value : String) : Int32
  value == "x" ? 10 : value == "shadow" ? 20 : -10
end

def item_tag(value : Int64) : Int32
  value == 9_i64 ? 30 : -30
end

def item_tag(value : Int32) : Int32
  -40
end

def memo_tag(value : Int32) : Int32
  value == 5_i32 ? 1 : value == 6_i32 ? 1 : value == 7_i32 ? 1 : -1
end

def memo_tag(value : Int64) : Int32
  value == 5_i64 ? 2 : value == 6_i64 ? 2 : value == 7_i64 ? 2 : -2
end

def memo_tag(value : Float64) : Int32
  value == 7.5_f64 ? 3 : -3
end

no_return_i32_tag = 0
no_return_i32 = GenericFlow(Int64).new.carry(5_i32) do |item, memo|
  no_return_i32_tag = item_tag(item) * 10 + memo_tag(memo)
end

no_return_i64_tag = 0
no_return_i64 = GenericFlow(Int64).new.carry(6_i64) do |item, memo|
  no_return_i64_tag = item_tag(item) * 10 + memo_tag(memo)
end

no_return_f64_tag = 0
no_return_f64 = GenericFlow(Int64).new.carry(7.5_f64) do |item, memo|
  no_return_f64_tag = item_tag(item) * 10 + memo_tag(memo)
end

annotated_i32_tag = 0
annotated_i32 = GenericFlow(Int64).new.carry_annotated(5_i32) do |item, memo|
  annotated_i32_tag = item_tag(item) * 10 + memo_tag(memo)
end

annotated_i64_tag = 0
annotated_i64 = GenericFlow(Int64).new.carry_annotated(6_i64) do |item, memo|
  annotated_i64_tag = item_tag(item) * 10 + memo_tag(memo)
end

annotated_f64_tag = 0
annotated_f64 = GenericFlow(Int64).new.carry_annotated(7.5_f64) do |item, memo|
  annotated_f64_tag = item_tag(item) * 10 + memo_tag(memo)
end

twice_i32_first_tag = 0
twice_i32_first = GenericFlow(Int64).new.carry_twice(5_i32, 6_i64) do |item, left, right|
  twice_i32_first_tag = item_tag(item) * 100 + memo_tag(left) * 10 + memo_tag(right)
end

twice_i64_first_tag = 0
twice_i64_first = GenericFlow(Int64).new.carry_twice(6_i64, 5_i32) do |item, left, right|
  twice_i64_first_tag = item_tag(item) * 100 + memo_tag(left) * 10 + memo_tag(right)
end

other_tag = 0
other_result = OtherGenericFlow(Int64).new.carry(5_i32) do |item, memo|
  other_tag = item_tag(item) * 10 + memo_tag(memo)
end

direct_tag = 0
direct_result = DirectShadowFlow(Int64).new.carry(6_i64) do |memo|
  direct_tag = memo_tag(memo)
end

receiver_tag = 0
receiver_result = ReceiverBox(Int64).new.carry_receiver(7_i64) do |memo|
  receiver_tag = memo_tag(memo)
end

ok = no_return_i32_tag == 101 && no_return_i32 == 5_i32 &&
     no_return_i64_tag == 102 && no_return_i64 == 6_i64 &&
     no_return_f64_tag == 103 && no_return_f64 == 7.5_f64 &&
     annotated_i32_tag == 101 && annotated_i32 == 5_i32 &&
     annotated_i64_tag == 102 && annotated_i64 == 6_i64 &&
     annotated_f64_tag == 103 && annotated_f64 == 7.5_f64 &&
     twice_i32_first_tag == 1011 && twice_i32_first == 5_i32 &&
     twice_i64_first_tag == 1022 && twice_i64_first == 6_i64 &&
     other_tag == 301 && other_result == 5_i32 &&
     direct_tag == 2 && direct_result == 6_i64 &&
     receiver_tag == 2 && receiver_result == 7_i64

LibC.exit(ok ? 0 : 9)
CR

if ! env -u CRYSTAL_PATH ADAMAS_LLVM_CACHE=0 \
    RUN_SAFE_RESOURCE_FILE="$TMP_DIR/hir.resources" \
    "$RUN_SAFE" "$COMPILER" 180 8192 \
    "$SRC" --no-prelude --emit hir --no-link -o "$OUT" \
    >"$TMP_DIR/hir.log" 2>&1; then
  echo "included forall shadow regression failed: HIR compilation failed" >&2
  tail -100 "$TMP_DIR/hir.log" >&2 || true
  exit 1
fi
if [[ ! -s "$HIR" ]]; then
  echo "included forall shadow regression failed: missing HIR output" >&2
  tail -100 "$TMP_DIR/hir.log" >&2 || true
  exit 1
fi

if ! env -u CRYSTAL_PATH ADAMAS_LLVM_CACHE=0 \
    RUN_SAFE_RESOURCE_FILE="$TMP_DIR/build.resources" \
    "$RUN_SAFE" "$COMPILER" 180 8192 "$SRC" --no-prelude -o "$BIN" \
    >"$TMP_DIR/build.log" 2>&1; then
  echo "included forall shadow regression failed: linked build failed" >&2
  tail -100 "$TMP_DIR/build.log" >&2 || true
  exit 1
fi

set +e
RUN_SAFE_RESOURCE_FILE="$TMP_DIR/run.resources" \
  "$RUN_SAFE" "$BIN" 10 512 >"$TMP_DIR/run.log" 2>&1
run_rc=$?
set -e
if [[ "$run_rc" != "0" ]]; then
  echo "included forall shadow regression failed: expected typed block dispatch, got exit $run_rc" >&2
  cat "$TMP_DIR/run.log" >&2
  exit 1
fi

echo "included method forall shadow regression passed"
