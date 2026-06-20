#!/usr/bin/env bash
# Diagnostic regression for the leaf-storage-POD gate narrowing (step-(a)).
#
# leaf_storage_pod_struct? must classify a struct as InlineValueCopy ONLY when
# every field is a primitive/enum leaf. A raw-pointer field is NOT value-copy-safe
# (inline copy duplicates a live interior pointer) → such structs must classify as
# ExistingLowering.
#
# Asserts, via the read-only [ELEM_REPR] census (gate ADAMAS_INLINE_POD_CONTAINERS):
#   (1) Vec2    => InlineValueCopy   (all-Int32 leaf fields)
#   (2) Vec3    => InlineValueCopy
#   (3) WithPtr => ExistingLowering  (carries a raw Pointer(Int32) field)
#   (4) GATE NEUTRALITY: gate ON vs OFF LLVM IR byte-identical once the pre-existing
#       non-deterministic @.stub_name_<hash> symbols are normalized (the repr label
#       is stored on the Type but consumed by no codegen path → read-only).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/leaf_pod_struct_pointer_field_repro.cr"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafpod.XXXXXX")"
CENSUS_ERR="$TMP_DIR/census.err"
LL_OFF="$TMP_DIR/off.norm.ll"
LL_ON="$TMP_DIR/on.norm.ll"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -f "$SRC" ]]; then
  echo "missing reducer source: $SRC"
  exit 2
fi

set +e
ADAMAS_INLINE_POD_CONTAINERS=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>"$CENSUS_ERR"
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "census compile failed (status $status); tmp_dir=$TMP_DIR"
  grep "ELEM_REPR" "$CENSUS_ERR" || true
  exit 2
fi

echo "compiler: $COMPILER"
grep -E "ELEM_REPR\] (Vec2|Vec3|WithPtr) " "$CENSUS_ERR"

fail=0
assert_repr() {
  local name="$1" want="$2"
  if ! grep -qE "\[ELEM_REPR\] $name kind=Struct => $want\$" "$CENSUS_ERR"; then
    echo "FAIL: $name expected => $want"
    fail=1
  fi
}

assert_repr "Vec2" "InlineValueCopy"
assert_repr "Vec3" "InlineValueCopy"
assert_repr "WithPtr" "ExistingLowering"

# (4) gate neutrality: ON vs OFF IR identical modulo stub-name hashes.
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null || true
ADAMAS_INLINE_POD_CONTAINERS=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/on" >/dev/null 2>/dev/null || true
sed -E 's/stub_name_[0-9]+/stub_name_N/g' "$TMP_DIR/off.ll" > "$LL_OFF"
sed -E 's/stub_name_[0-9]+/stub_name_N/g' "$TMP_DIR/on.ll"  > "$LL_ON"
norm_diff="$(diff "$LL_OFF" "$LL_ON" | grep -c '^[<>]' || true)"
if [[ "$norm_diff" != "0" ]]; then
  echo "FAIL: gate ON vs OFF IR differs ($norm_diff normalized lines) — label populate is not read-only"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "tmp_dir: $TMP_DIR"
  exit 1
fi

echo "ok: leaf gate narrowed — Vec2/Vec3 InlineValueCopy, raw-pointer-field WithPtr ExistingLowering; gate neutral (normalized IR diff=0)"
exit 0
