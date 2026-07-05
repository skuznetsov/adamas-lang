#!/usr/bin/env bash
# Repro: return-type resolution for a callsite WITH args served the base-name
# representative (`@function_base_return_types["Random::PCG32#rand"]` /
# the first `@function_defs[base]` hit), i.e. the ZERO-ARG overload
# `def rand : Float64`, instead of the matching-arity overload
# `def rand(max : Int) : Int`. Every `r.rand(n)` was statically typed Float64:
#   - typeof(r.rand(10)) == Float64 (host: Int32);
#   - interpolation "#{Random.rand(...)}" demanded Float64#to_s ->
#     Ryu Printer.shortest STUB abort in stage2-built compilers
#     (the s2 File.tempname parallel-emission blocker after 92c42aed).
#
# Fix: positional-arity gate (call_arg_count) threaded through
# lookup_function_def_for_return / resolve_return_type_from_def /
# get_function_return_type; base-name cache no longer serves typed
# specializations at arity-aware callsites.
#
# Red pre-fix : both typeof lines print Float64.
# Green       : integer types (Int32 today; the exact width may become Int64
#               once the abstract-`: Int`-return sibling is fixed, so the gate
#               is "not Float", see rand_int64_abstract_int_return_repro.sh).
# NOTE: VALUE correctness of rand(0x100000000) is deliberately not asserted
# here — that is the open abstract-Int-return sibling, not this fix.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rand_overload_ret.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
cat > "$SRC" <<'CR'
r = Random.new
puts typeof(r.rand(10))
puts typeof(Random.rand(0x100000000))
CR

if ! "$COMPILER" "$SRC" -o "$OUT" > "$TMP_DIR/compile.log" 2>&1; then
  echo "FAIL: compile error" >&2
  tail -5 "$TMP_DIR/compile.log" >&2
  exit 1
fi

OUTPUT="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
LINE1="$(echo "$OUTPUT" | sed -n 1p)"
LINE2="$(echo "$OUTPUT" | sed -n 2p)"

FAIL=0
case "$LINE1" in
  Int*|UInt*) ;;
  *) echo "FAIL: typeof(r.rand(10)) = '$LINE1' (expected an Int type, host Int32)" >&2; FAIL=1 ;;
esac
case "$LINE2" in
  Int*|UInt*) ;;
  *) echo "FAIL: typeof(Random.rand(0x100000000)) = '$LINE2' (expected an Int type)" >&2; FAIL=1 ;;
esac

if [[ "$FAIL" != 0 ]]; then
  exit 1
fi
echo "PASS: argful rand callsites typed from the matching-arity overload ($LINE1/$LINE2)"
