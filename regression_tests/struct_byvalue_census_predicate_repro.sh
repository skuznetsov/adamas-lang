#!/usr/bin/env bash
# Regression test: the by-value struct census eligibility predicate
# (ADAMAS_STRUCT_BYVALUE_CENSUS, read-only/diagnostic) must distinguish a
# DEFINITE recursive-POD struct from one that only looks POD at the top level.
#
# Finding 3 (GPT round-2): the coarse proxy struct_type_is_pod? uses
# type_needs_rc?, which does NOT recurse through struct fields, so a struct whose
# direct field is another struct that transitively holds a String/ref is
# mis-counted as POD. A by-value flip gated on the coarse proxy would raw-memcpy
# such a struct and duplicate an owned inner pointer with no retain/release
# -> UAF/leak under ARC.
#
# This pins struct_type_is_recursive_pod? against that regression:
#   - PodPair { @a, @b : Int32 }            -> recursive POD = TRUE
#   - Outer   { @inner : Inner{ @s:String } } -> coarse says POD, recursive = FALSE
#     (the exact coarse-POD over-count case)
#
# Gated diagnostic only: no codegen change. The test asserts census output, not
# program behavior.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/struct_byval_census.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC='struct PodPair
  @a : Int32
  @b : Int32
  def initialize(@a : Int32, @b : Int32)
  end
  def a : Int32
    @a
  end
end

struct Inner
  @s : String
  def initialize(@s : String)
  end
  def s : String
    @s
  end
end

struct Outer
  @inner : Inner
  def initialize(@inner : Inner)
  end
  def inner : Inner
    @inner
  end
end

p = PodPair.new(1, 2)
o = Outer.new(Inner.new("hi"))
STDERR.puts(p.a + o.inner.s.size)'

CR="$TMP_DIR/repro.cr"
printf '%s' "$SRC" >"$CR"
fail=0

# One census compile filtered to a type; prints per-type rec_pod lines + the
# global counters. Returns the captured stderr in $OUT.
census() {
  local type_filter="$1"
  local bin="$TMP_DIR/repro_${type_filter}.bin"
  ADAMAS_STRUCT_BYVALUE_CENSUS=1 ADAMAS_STRUCT_BYVALUE_CENSUS_TYPE="$type_filter" \
    "$COMPILER" "$CR" -o "$bin" >"$TMP_DIR/out_${type_filter}" 2>&1 || {
      echo "FAIL: compile error (filter=$type_filter)"; cat "$TMP_DIR/out_${type_filter}"; exit 1; }
  OUT="$(cat "$TMP_DIR/out_${type_filter}")"
}

# 1) Outer: nested String -> recursive POD must be FALSE, and it must be counted
#    in coarse_pod_overcount (coarse true, recursive false).
census Outer
if ! grep -q 'BYVAL_CENSUS\].*rec_pod=false.*type=Outer' <<<"$OUT"; then
  echo "FAIL: Outer (nested String) not reported rec_pod=false"; echo "$OUT" | grep BYVAL_CENSUS; fail=1
fi
overcount="$(grep -oE 'coarse_pod_overcount=[0-9]+' <<<"$OUT" | head -1 | cut -d= -f2)"
if [[ -z "${overcount:-}" || "$overcount" -lt 1 ]]; then
  echo "FAIL: coarse_pod_overcount expected >=1, got '${overcount:-<none>}'"; fail=1
fi

# 2) PodPair: all-Int32 -> recursive POD must be TRUE.
census PodPair
if ! grep -q 'BYVAL_CENSUS\].*rec_pod=true.*type=PodPair' <<<"$OUT"; then
  echo "FAIL: PodPair (all Int32) not reported rec_pod=true"; echo "$OUT" | grep BYVAL_CENSUS; fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "struct_byvalue_census_predicate_ok"
  exit 0
else
  echo "struct_byvalue_census_predicate FAILED"
  exit 1
fi
