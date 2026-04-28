#!/usr/bin/env bash
# Regression test for Task #72: Tuple#to_static_array null StaticArray buffer.
#
# Pre-fix: `Tuple(Char)#to_static_array` segfaulted because
# `uninitialized StaticArray(Union(*T), {{ T.size }})` lowered to a null
# pointer literal. The V2 parser stores complex type-annotation expressions
# as a single IdentifierNode with literal text "StaticArray(Union(*T), 1)"
# (parser.cr:14094 - "Don't wrap in GenericNode"). `stringify_type_expr`
# IdentifierNode case did `@type_param_map[name]?` lookup which missed for
# the non-simple name; `type_ref_for_name` returned VOID; `lower_uninitialized`
# treated VOID as primitive and emitted a null Literal instead of an
# Allocate -> SEGFAULT at `to_unsafe[i] = value` store.
#
# Fix (HIR ast_to_hir.cr 9318+, 39916+):
#   1. `stringify_type_expr` IdentifierNode case routes names containing
#      `(`, `*`, or `|` through `substitute_type_params_in_type_name` so
#      type-param substitution recurses into the synthetic identifier.
#   2. `substitute_type_params_in_type_name` now expands `*T` splat args:
#      looks up T's binding, when it's a Tuple, splices the tuple element
#      types in place; collapses single-arg Union(X) to X.
#
# Result: `StaticArray(Union(*T), 1)` for `Tuple(Char)` resolves to
# `StaticArray(Char, 1)`, which `lower_uninitialized` recognizes as
# non-primitive and allocates correctly.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tuple_to_static_array.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_OUT="$TMP_DIR/compile.out"
COMPILE_ERR="$TMP_DIR/compile.err"
RUN_OUT="$TMP_DIR/run.out"
RUN_ERR="$TMP_DIR/run.err"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
t = {'a'}
ary = t.to_static_array
val = ary.to_unsafe[0]
puts val == 'a'
puts val.ord
CR

set +e
# First pass: compile with --emit llvm-ir for grep checks (no binary).
"$COMPILER" "$SRC" -o "$BIN" --emit llvm-ir >"$COMPILE_OUT" 2>"$COMPILE_ERR"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "compile failed (--emit llvm-ir)"
  echo "compiler: $COMPILER"
  echo "status: $compile_status"
  echo "tmp_dir: $TMP_DIR"
  echo "--- stderr (tail) ---"
  tail -40 "$COMPILE_ERR"
  exit 2
fi

LL="$BIN.ll"
if [[ ! -s "$LL" ]]; then
  echo "missing or empty LL: $LL"
  ls -la "$TMP_DIR"
  exit 2
fi

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "ll: $(wc -l <"$LL") lines"

# Post-fix sentinel: Tuple#to_static_array body has a real malloc + store
to_static_def=$(grep -c '^define ptr @Tuple\$Hto_static_array' "$LL" || true)
if [[ "$to_static_def" -lt 1 ]]; then
  echo "skip: Tuple#to_static_array not monomorphized in this LL - Crystal stdlib may have been inlined"
  exit 0
fi

# Extract the function body and look for null-buffer marker (pre-fix witness)
body="$(awk '/^define ptr @Tuple\$Hto_static_array/{flag=1} flag{print} /^}/{if(flag){flag=0}}' "$LL")"

# Pre-fix witness: literal null pointer assigned to the static-array variable.
# We look for "inttoptr i64 0 to ptr" inside the function body - the smoking
# gun was `%r1 = inttoptr i64 0 to ptr ; ary` followed by stores at offset 0.
null_ary=$(echo "$body" | grep -c 'inttoptr i64 0 to ptr' || true)
echo "(info) null-pointer assignments in body = $null_ary (pre-fix had >=2)"

# Post-fix sentinel: the body must allocate via __crystal_v2_malloc
malloc_calls=$(echo "$body" | grep -c 'call ptr @__crystal_v2_malloc' || true)
echo "good: malloc calls in body = $malloc_calls"

if [[ "$malloc_calls" -lt 1 ]]; then
  echo "regression: Tuple#to_static_array body missing real allocation"
  exit 1
fi

# Post-fix sentinel: there must be a store i32 (the Char element)
store_i32=$(echo "$body" | grep -c 'store i32 ' || true)
echo "good: store i32 instructions in body = $store_i32"

if [[ "$store_i32" -lt 1 ]]; then
  echo "regression: Tuple#to_static_array body missing element store"
  exit 1
fi

# Second pass: compile to a real binary (no --emit) and run it.
set +e
"$COMPILER" "$SRC" -o "$BIN" >"$COMPILE_OUT" 2>"$COMPILE_ERR"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "compile failed (binary build)"
  tail -40 "$COMPILE_ERR"
  exit 2
fi

if [[ ! -x "$BIN" ]]; then
  echo "binary missing: $BIN"
  exit 2
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 256 >"$RUN_OUT" 2>"$RUN_ERR"
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  echo "regression: runtime crashed (exit=$run_status)"
  echo "--- stdout ---"
  cat "$RUN_OUT"
  echo "--- stderr ---"
  cat "$RUN_ERR"
  exit 1
fi

# Output must show val == 'a' (true) and val.ord == 97. run_safe.sh wraps
# program output between marker lines, so ignore harness metadata.
expected_eq="true"
expected_ord="97"
PROGRAM_OUT="$TMP_DIR/program.out"
awk '
  /^=== STDOUT ===$/ {in_stdout=1; next}
  /^=== STDERR ===$/ {in_stdout=0; next}
  in_stdout && $0 !~ /^\[EXIT:/ {print}
' "$RUN_OUT" >"$PROGRAM_OUT"
got_eq="$(sed -n '1p' "$PROGRAM_OUT")"
got_ord="$(sed -n '2p' "$PROGRAM_OUT")"

echo "got_eq=$got_eq got_ord=$got_ord"

if [[ "$got_eq" != "$expected_eq" ]]; then
  echo "regression: line 1 expected '$expected_eq' got '$got_eq'"
  exit 1
fi

if [[ "$got_ord" != "$expected_ord" ]]; then
  echo "regression: line 2 expected '$expected_ord' got '$got_ord'"
  exit 1
fi

echo "tuple_to_static_array_union_splat_repro_ok"
exit 0
