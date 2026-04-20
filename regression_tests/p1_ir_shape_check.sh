#!/bin/bash
# Additive shape guard for the hybrid closure-env ABI P1 boundary.
#
# This is not a full behavior regression. It asserts the current intended
# compiler shape for heap Proc materialization while legacy raw block paths are
# still being cleaned up:
#   - HIR exposes boxed capture metadata in make_closure dumps.
#   - HIR materializes user-visible Proc values via make_proc.
#   - Proc#call sites in the focused heap block path do not carry hidden
#     capture arguments.
#   - LLVM keeps Proc values pointer-shaped and uses %__crystal_proc only as a
#     pointee layout.
#   - The captured block body receives ptr %__closure_env and reads through it,
#     not through a closure-cell global.
#   - The heap Proc object stores fn@0/env@8 and the call dispatch passes env to
#     captureful functions.
#
# Exit semantics:
#   exit 0 — shape matches the current P1 boundary.
#   exit 1 — shape regression.
#   exit 2 — inconclusive compile/setup failure.

set -u

COMPILER="${1:-}"
if [[ -z "$COMPILER" ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

if [[ ! -x "$COMPILER" ]]; then
  echo "inconclusive: compiler not executable: $COMPILER" >&2
  exit 2
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/p1_ir_shape_probe.cr"
OUT_BASE="$TMPDIR/p1_ir_shape_probe"
HIR="$OUT_BASE.hir"
LL_BASE="$TMPDIR/p1_ir_shape_probe_ll"
LL="$LL_BASE.ll"

cat > "$SRC" <<'EOF'
def call_block(&block : ->)
  block.call
end

x = 10
call_block do
  x = 42
end
puts x

p = ->(y : Int32) { y + 1 }
puts p.call(4)
EOF

fail() {
  echo "shape regression: $*" >&2
  exit 1
}

inconclusive() {
  echo "inconclusive: $*" >&2
  exit 2
}

extract_body() {
  local symbol="$1"
  local src_file="$2"
  local dest_file="$3"

  awk -v symbol="$symbol" '
    $0 ~ "^define .*@" symbol "\\(" { in_body = 1 }
    in_body { print }
    in_body && $0 == "}" { exit }
  ' "$src_file" > "$dest_file"
}

CRYSTAL_V2_STOP_AFTER_HIR=1 "$COMPILER" "$SRC" --emit hir -o "$OUT_BASE" \
  >"$TMPDIR/hir.out" 2>"$TMPDIR/hir.err" ||
  inconclusive "failed to emit HIR ($(tail -20 "$TMPDIR/hir.err" | tr '\n' ' '))"

"$COMPILER" "$SRC" --emit llvm-ir --no-link -o "$LL_BASE" \
  >"$TMPDIR/ll.out" 2>"$TMPDIR/ll.err" ||
  inconclusive "failed to emit LLVM IR ($(tail -20 "$TMPDIR/ll.err" | tr '\n' ' '))"

[[ -f "$HIR" ]] || inconclusive "missing HIR artifact: $HIR"
[[ -f "$LL" ]] || inconclusive "missing LLVM artifact: $LL"

grep -Eq 'make_closure .*captures=\[.* boxed slot=[0-9]+ payload=[0-9]+ by_ref' "$HIR" ||
  fail "HIR make_closure dump does not expose boxed slot/payload metadata"

grep -Eq 'make_proc fn=%[0-9]+ env=%[0-9]+' "$HIR" ||
  fail "HIR does not materialize Proc values with make_proc"

CAPTURED_FN=$(awk '
  /func_pointer @__crystal_block_proc_[0-9]+/ {
    if (match($0, /@__crystal_block_proc_[0-9]+/)) {
      last_fn = substr($0, RSTART + 1, RLENGTH - 1)
    }
  }
  /make_closure .* boxed slot=[0-9]+ payload=[0-9]+ by_ref/ {
    if (last_fn != "") {
      print last_fn
      exit
    }
  }
' "$HIR")

[[ -n "$CAPTURED_FN" ]] ||
  fail "could not identify focused captured block function from HIR"

CAPTURED_MAKE_LINE=$(grep -En 'make_closure .* boxed slot=[0-9]+ payload=[0-9]+ by_ref' "$HIR" | head -1 | cut -d: -f1)
[[ -n "$CAPTURED_MAKE_LINE" ]] ||
  fail "could not locate focused boxed make_closure line"

CAPTURED_HIR_WINDOW="$TMPDIR/captured_make_proc.hir"
sed -n "${CAPTURED_MAKE_LINE},$((CAPTURED_MAKE_LINE + 10))p" "$HIR" > "$CAPTURED_HIR_WINDOW"

grep -Eq 'make_proc fn=%[0-9]+ env=%[0-9]+' "$CAPTURED_HIR_WINDOW" ||
  fail "boxed make_closure is not immediately wrapped in make_proc"

grep -Eq 'Proc#call\$[*]T_splat\(\)' "$CAPTURED_HIR_WINDOW" ||
  fail "focused heap block Proc#call is not emitted as a zero-user-arg call"

if grep -Eq 'Proc#call\$[*]T_splat\([^)]' "$CAPTURED_HIR_WINDOW"; then
  fail "focused heap block Proc#call still carries hidden capture arguments"
fi

grep -Eq 'literal 0 : Pointer' "$HIR" ||
  fail "zero-capture proc no longer uses null env in HIR"

if grep -Eq '(load|store|alloca) %__crystal_proc|define .*%__crystal_proc|call .*%__crystal_proc' "$LL"; then
  fail "LLVM uses %__crystal_proc as a by-value Proc representation"
fi

CAPTURED_LL_BODY="$TMPDIR/captured_fn.ll"
extract_body "$CAPTURED_FN" "$LL" "$CAPTURED_LL_BODY"
[[ -s "$CAPTURED_LL_BODY" ]] ||
  fail "missing LLVM body for $CAPTURED_FN"

grep -Eq "^define .*@$CAPTURED_FN\\(ptr %__closure_env\\)" "$CAPTURED_LL_BODY" ||
  fail "$CAPTURED_FN does not receive ptr %__closure_env"

grep -Eq 'getelementptr i8, ptr %__closure_env' "$CAPTURED_LL_BODY" ||
  fail "$CAPTURED_FN does not read captures through %__closure_env"

if grep -Eq '@__closure__classvar____closure_cell' "$CAPTURED_LL_BODY"; then
  fail "$CAPTURED_FN still reads or writes closure-cell globals"
fi

STORE_LINE=$(grep -En "store ptr @$CAPTURED_FN, ptr" "$LL" | head -1 | cut -d: -f1)
[[ -n "$STORE_LINE" ]] ||
  fail "heap Proc object does not store $CAPTURED_FN as fn@0"

PROC_OBJECT_WINDOW="$TMPDIR/proc_object.ll"
sed -n "$((STORE_LINE - 5)),$((STORE_LINE + 20))p" "$LL" > "$PROC_OBJECT_WINDOW"

grep -Eq 'getelementptr i8, ptr %[A-Za-z0-9_.]+, i32 8' "$PROC_OBJECT_WINDOW" ||
  fail "heap Proc object does not compute env@8 near fn store"

grep -Eq 'store ptr %[A-Za-z0-9_.]+, ptr %[A-Za-z0-9_.]+' "$PROC_OBJECT_WINDOW" ||
  fail "heap Proc object does not store a non-null env pointer near fn store"

CALL_WINDOW="$TMPDIR/proc_call.ll"
sed -n "${STORE_LINE},$((STORE_LINE + 90))p" "$LL" > "$CALL_WINDOW"

grep -Eq '__crystal_v2_null_fn_guard' "$CALL_WINDOW" ||
  fail "heap Proc dispatch does not guard the loaded function pointer"

grep -Eq 'call .*%[A-Za-z0-9_.]+\(ptr %[A-Za-z0-9_.]+\)' "$CALL_WINDOW" ||
  fail "heap Proc dispatch does not pass env to the captureful function"

echo "p1_ir_shape_ok captured_fn=$CAPTURED_FN"
