#!/usr/bin/env bash
# Regression test: a small (<=8B) user struct used as a TUPLE element must read
# back correctly under the step-4 small-struct inline ABI
# (ADAMAS_INLINE_SMALL_STRUCTS=1).
#
# Bug (step-4 only): register_tuple_types lays out a struct tuple element as an
# 8-byte POINTER CARRIER (container regime, unaffected by step-4). But
# lower_field_get / lower_field_store_to_ptr routed EVERY struct field through
# LayoutContract.user_struct_inline?, which under step-4 returns true for a small
# struct -> the tuple element FieldGet returned a BorrowedAddress (inline bytes)
# instead of LOADING the carrier pointer. The destructured element then read
# garbage, so the sum came out wrong. gate-OFF was correct (user_struct_inline?
# returns false for a small struct), so the two gates diverged -> a repr-flip.
#
# Fix (hir_to_mir.cr): in lower_field_get and lower_field_store_to_ptr, detect a
# Tuple/NamedTuple receiver (field_receiver_is_tuple? / obj_mir_type kind tuple?)
# and suppress ONLY the step-4 small-struct flip (size <= pointer word) for it,
# so a tuple element follows the container pointer-carrier regime that
# register_tuple_types actually wrote. Large structs (> pointer word) are inline
# in both regimes and are left unchanged.
#
# The literal `{EId.new(..), a}` has element type `A`, but the array element type
# is the union `AB`, so it goes through try_coerce_tuple_to_tuple -> the FieldGet
# `@__0` on the small struct element is exactly the leak point. Both gates must
# print the same correct result.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tuple_small_struct.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC='struct EId
  @index : Int32
  def initialize(@index : Int32)
  end
  def index : Int32
    @index
  end
end

class A
end

class B
end

alias AB = A | B

items = [] of Tuple(EId, AB)
a = A.new
# {EId, A} coerces to Tuple(EId, AB): try_coerce_tuple_to_tuple FieldGets @__0
# (the small struct) -> the exact step-4 repr-flip leak point.
items << {EId.new(10), a}
items << {EId.new(20), a}

sum = 0
items.each do |(eid, _x)|
  sum += eid.index
end

STDERR.puts(sum == 30 ? "tuple_small_struct_ok" : "tuple_small_struct_bad")
puts(sum == 30 ? "tuple_small_struct_ok" : "tuple_small_struct_bad")'

fail=0

# Compile + run under a given gate value and assert stdout == tuple_small_struct_ok.
run_gate() {
  local label="$1" gate="$2"
  local cr="$TMP_DIR/repro.cr" bin="$TMP_DIR/repro_$label.bin" out="$TMP_DIR/repro_$label.out"
  printf '%s' "$SRC" >"$cr"
  if ! ADAMAS_INLINE_SMALL_STRUCTS="$gate" "$COMPILER" "$cr" -o "$bin" \
        >"$TMP_DIR/compile_$label" 2>&1; then
    echo "FAIL[$label]: compile error (gate=$gate)"; cat "$TMP_DIR/compile_$label"; fail=1; return
  fi
  set +e
  "$bin" >"$out" 2>/dev/null
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "FAIL[$label]: runtime crash (gate=$gate, exit $rc)"; fail=1; return
  fi
  local got; got="$(cat "$out")"
  if [[ "$got" != "tuple_small_struct_ok" ]]; then
    echo "FAIL[$label]: expected [tuple_small_struct_ok] got [$got] (gate=$gate)"; fail=1; return
  fi
  echo "PASS[$label]: tuple_small_struct_ok (gate=$gate)"
}

run_gate gate_off 0
run_gate gate_on 1

if [[ $fail -ne 0 ]]; then
  echo "RESULT: FAIL"; exit 1
fi
echo "RESULT: PASS"
