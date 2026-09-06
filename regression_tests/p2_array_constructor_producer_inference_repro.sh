#!/usr/bin/env bash
# Regression: filled and block Array.new calls must infer their element type
# from the value producer. The surrounding function's return type is an
# unrelated Array(Entry); using it for every bare generic Array.new changes
# Array(Int32), Array(Bool), and Array(Array(Int32)) into Array(Entry).
#
# This is deliberately no-prelude. Declaring Array(T) here registers the
# generic template while keeping the source small enough for a focused HIR
# check. The absolute ::Array spellings exercise the same path through the
# namespace-qualified constructor lookup.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/p2_array_constructor_producer.XXXXXX")"

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

run_checked() {
  local label="$1"
  local log="$2"
  shift 2
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$@" >"$log" 2>&1; then
    echo "FAIL: $label" >&2
    cat "$log" >&2
    exit 1
  fi
}

MIXED_SRC="$TMP_DIR/mixed.cr"
MIXED_HIR_BASE="$TMP_DIR/mixed"
MIXED_HIR="$MIXED_HIR_BASE.hir"
MIXED_BIN="$TMP_DIR/mixed.bin"
MIXED_HIR_LOG="$TMP_DIR/mixed-hir.log"
MIXED_COMPILE_LOG="$TMP_DIR/mixed-compile.log"
MIXED_RUN_LOG="$TMP_DIR/mixed-run.log"
MIXED_METHOD_HIR="$TMP_DIR/reorder.hir"
RUNTIME_SRC="$TMP_DIR/mixed-runtime.cr"

cat >"$MIXED_SRC" <<'CR'
class Array(T)
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Entry
  getter value : Int32

  def initialize(@value : Int32)
  end
end

def reorder(bucket : Array(Entry)) : Array(Entry)
  # Filled Int32: the function return type is Array(Entry), but the producer
  # value is the Int32 literal.
  counts = Array.new(bucket.size, 0)
  counts[0] += 1
  LibC.exit(31) unless counts[0] == 1

  # Absolute lookup must preserve the Bool producer too.
  flags = ::Array.new(bucket.size, false)
  LibC.exit(33) unless flags[0] == false

  # The block produces a nested Array(Int32), independent of the return type.
  outgoing = ::Array.new(bucket.size) { [] of Int32 }
  outgoing[0] << 9
  LibC.exit(34) unless outgoing[0][0] == 9

  bucket
end

bucket = [Entry.new(7)]
result = reorder(bucket)
LibC.exit(32) unless result[0].value == 7
LibC.exit(0)
CR

run_checked "mixed HIR compile" "$MIXED_HIR_LOG" \
  "$COMPILER" 120 8192 "$MIXED_SRC" --no-prelude --emit=hir --no-link -o "$MIXED_HIR_BASE"

if [[ ! -s "$MIXED_HIR" ]]; then
  echo "FAIL: mixed HIR output is missing" >&2
  cat "$MIXED_HIR_LOG" >&2 || true
  exit 1
fi

LC_ALL=C awk '
  /^func @reorder\$Array\(Entry\)/ { inside = 1 }
  inside && /^func @/ && !/^func @reorder\$Array\(Entry\)/ { exit }
  inside { print }
' "$MIXED_HIR" >"$MIXED_METHOD_HIR"

if [[ ! -s "$MIXED_METHOD_HIR" ]]; then
  echo "FAIL: reorder HIR function is missing" >&2
  rg -n 'reorder|Array\(' "$MIXED_HIR" >&2 || true
  exit 1
fi

# These producer-specific HIR forms are the focused guard. Type IDs are
# intentionally not asserted: their numbering changes as the compiler grows.
for pattern in \
  'extern_call @__adamas_array_new_filled_i32' \
  'extern_call @__adamas_array_new_filled_bool' \
  'call Array(Array(Int32)).new$Int32_block'; do
  if ! LC_ALL=C grep -aFq "$pattern" "$MIXED_METHOD_HIR"; then
    echo "FAIL: missing producer-specific HIR pattern: $pattern" >&2
    cat "$MIXED_METHOD_HIR" >&2
    exit 1
  fi
done

if LC_ALL=C grep -aFq 'Array(Entry)).new' "$MIXED_METHOD_HIR"; then
  echo "FAIL: Array.new borrowed the enclosing Array(Entry) return type" >&2
  cat "$MIXED_METHOD_HIR" >&2
  exit 1
fi

# The no-prelude source above is the focused template-registration probe. Run
# the same program with the original prelude for the behavioral check; keeping
# the local `class Array(T)` declaration out of this compile avoids replacing
# the stdlib Array implementation with the intentionally empty probe template.
tail -n +3 "$MIXED_SRC" >"$RUNTIME_SRC"
run_checked "mixed binary compile" "$MIXED_COMPILE_LOG" \
  "$COMPILER" 180 8192 "$RUNTIME_SRC" -o "$MIXED_BIN"
run_checked "mixed binary runtime" "$MIXED_RUN_LOG" "$MIXED_BIN" 5 512

# Keep the older expected-return behavior covered in the same self-contained
# script. A bare non-Array generic constructor is still allowed to use the
# enclosing generic return type when it has no producer value to infer.
BAG_SRC="$TMP_DIR/bag.cr"
BAG_HIR_BASE="$TMP_DIR/bag"
BAG_HIR="$BAG_HIR_BASE.hir"
BAG_LOG="$TMP_DIR/bag-hir.log"
BAG_METHOD_HIR="$TMP_DIR/to-bag.hir"

cat >"$BAG_SRC" <<'CR'
module M(T)
end

module M
  def to_bag : Bag(T)
    Bag.new(self)
  end
end

class Bag(T)
  def initialize(other)
  end
end

class A(T)
  include M(T)
end

a = A(String).new
a.to_bag
CR

run_checked "legacy generic expected-return HIR compile" "$BAG_LOG" \
  "$COMPILER" 120 8192 "$BAG_SRC" --no-prelude --emit=hir --no-link -o "$BAG_HIR_BASE"

if [[ ! -s "$BAG_HIR" ]]; then
  echo "FAIL: legacy Bag HIR output is missing" >&2
  cat "$BAG_LOG" >&2 || true
  exit 1
fi

LC_ALL=C awk '
  /^func @A\(String\)#to_bag/ { inside = 1 }
  inside { print }
  inside && /^}/ { exit }
' "$BAG_HIR" >"$BAG_METHOD_HIR"

if [[ ! -s "$BAG_METHOD_HIR" ]]; then
  echo "FAIL: legacy A(String)#to_bag HIR function is missing" >&2
  rg -n 'to_bag|Bag\(' "$BAG_HIR" >&2 || true
  exit 1
fi

if LC_ALL=C grep -aFq 'Bag(A(String)).new' "$BAG_METHOD_HIR"; then
  echo "FAIL: legacy bare generic .new inferred the receiver object type" >&2
  cat "$BAG_METHOD_HIR" >&2
  exit 1
fi

if ! LC_ALL=C grep -aFq 'Bag(String).new$A(String)' "$BAG_METHOD_HIR"; then
  echo "FAIL: legacy bare generic .new lost its expected Bag(String) return type" >&2
  cat "$BAG_METHOD_HIR" >&2
  exit 1
fi

echo "p2_array_constructor_producer_inference_repro_ok"
