#!/bin/bash
# Falsifier reducer for P1 monotonic @boxed_locals invariant.
#
# Motivation: `.locals` truncation at branch/case merge sites is claimed
# safe under I14-monotonic (see ast_to_hir.cr BoxedLocal docs). The claim
# holds only if boxes are never introduced INSIDE a branch — they must be
# hoisted to a site that dominates every subsequent read/write.
#
# This reducer stresses the weakest form of that claim: a captured local
# used in a proc that is constructed inside one branch of an `if`. Even
# if the proc itself is one-branch-only, the captured variable lives in
# the PARENT scope. Under a correct monotonic design the box for that
# variable must be emitted at the parent function's entry (before the
# `if`), regardless of which branch builds the proc.
#
# Shape of the test program:
#   counter = 0
#   p = nil.as(Proc(Int32, Int32) | Nil)
#   if some_condition
#     p = ->(x : Int32) { counter += x; counter }
#   end
#   if proc = p
#     puts proc.call(7)
#   else
#     puts counter          # counter is 0 — no mutation happened
#   end
#
# Pre-flip behavior: boxed locals are empty, proc captures route through
# global `@__closure_cell_N` class vars, so this prints whatever the
# existing class-var path yields.
#
# Post-flip (P1 atomic) expected behavior:
#   - First branch builds the proc; the capture `counter` resolves to a
#     box pointer that was allocated at function entry.
#   - `proc.call(7)` reads counter=0 from the box, writes counter=7.
#   - The outer `puts` (executed after the call) would see 7 via the
#     shared box if we took both paths — but since we only reach the
#     `puts proc.call(7)` branch here, the assertion is `== 7`.
#
# Status: KNOWN-RED pre-P1 atomic flip. Exits 0 when bug reproduces
# (output does NOT contain "7"). Exits 1 when behavior is correct.

set -u

COMPILER="${1:-}"
if [[ -z "$COMPILER" ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/conditional_closure_capture.cr"
BIN="$TMPDIR/conditional_closure_capture"

cat > "$SRC" <<'EOF'
counter = 0
p = nil.as(Proc(Int32, Int32) | Nil)

if 1 + 1 == 2
  p = ->(x : Int32) { counter += x; counter }
end

if proc = p
  puts proc.call(7)
else
  puts counter
end
EOF

"$COMPILER" "$SRC" -o "$BIN" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "compile_failed"
  exit 0
fi

OUT=$("$BIN" 2>&1 || true)

if [[ "$OUT" == *"7"* ]]; then
  echo "correct: proc.call mutated boxed counter → 7"
  exit 1
else
  echo "reproduced: expected 7, got: $OUT"
  exit 0
fi
