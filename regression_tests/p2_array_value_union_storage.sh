#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cv2_array_value_union_storage.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat >"$SRC" <<'CR'
struct Pair
  @x : Int64
  @y : Int64

  def initialize(@x : Int64, @y : Int64)
  end

  def sum : Int64
    @x + @y
  end
end

def nilable_struct_sum : Int64
  arr = Array(Pair | Nil).new
  i = 0
  while i < 8
    if (i & 1) == 0
      arr << Pair.new(i.to_i64 + 10_i64, i.to_i64)
    else
      arr << nil
    end
    i += 1
  end

  sum = 0_i64
  i = 0
  while i < arr.size
    if pair = arr[i]
      sum += pair.sum
    else
      sum -= 1_i64
    end
    i += 1
  end
  sum
end

def mixed_struct_int_sum : Int64
  arr = Array(Pair | Int64).new
  i = 0
  while i < 8
    if (i & 1) == 0
      arr << Pair.new(i.to_i64 + 10_i64, i.to_i64)
    else
      arr << i.to_i64
    end
    i += 1
  end

  sum = 0_i64
  i = 0
  while i < arr.size
    value = arr[i]
    if value.is_a?(Pair)
      sum += value.sum
    else
      sum += value
    end
    i += 1
  end
  sum
end

def pointer_nilable_struct_sum : Int64
  ptr = Pointer(Pair | Nil).malloc(4)
  ptr[0] = Pair.new(20_i64, 1_i64)
  ptr[1] = nil
  ptr[2] = Pair.new(30_i64, 2_i64)
  ptr[3] = nil

  sum = 0_i64
  i = 0
  while i < 4
    if pair = ptr[i]
      sum += pair.sum
    else
      sum -= 1_i64
    end
    i += 1
  end
  sum
end

def shifted_array_compaction_sum : Int64
  arr = Array(Pair | Nil).new
  i = 0
  while i < 8
    arr << Pair.new(i.to_i64 + 10_i64, i.to_i64)
    i += 1
  end

  4.times { arr.shift }

  # The fifth push after shifting crosses Array#check_needs_resize's
  # root_buffer.copy_from path, which must copy full inline union slots.
  i = 8
  while i < 13
    arr << Pair.new(i.to_i64 + 10_i64, i.to_i64)
    i += 1
  end

  sum = 0_i64
  i = 0
  while i < arr.size
    if pair = arr[i]
      sum += pair.sum
    else
      sum -= 1000_i64
    end
    i += 1
  end
  sum
end

exit 1 unless nilable_struct_sum == 60_i64
exit 2 unless mixed_struct_int_sum == 80_i64
exit 3 unless pointer_nilable_struct_sum == 51_i64
exit 4 unless shifted_array_compaction_sum == 234_i64
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 build "$SRC" --release -o "$BIN" >"$LOG" 2>&1
compile_rc=$?
set -e

if [[ $compile_rc -ne 0 ]]; then
  echo "p2_array_value_union_storage_failed: compile failed" >&2
  tail -120 "$LOG" >&2 || true
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_rc=$?
set -e

if [[ $run_rc -ne 0 ]]; then
  echo "p2_array_value_union_storage_failed: run failed rc=$run_rc" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "p2_array_value_union_storage_ok"
