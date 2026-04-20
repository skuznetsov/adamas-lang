#!/bin/bash
# Focused guard for the still-intentional raw block-callback path.
#
# Methods that use `yield` directly still receive raw function pointers for
# their block callbacks. The full heap Proc path is only for proc literals and
# selected block-to-proc conversions where the callee stores/calls `block.call`.
#
# This guard pins the current raw callback shape for a mutable captured local:
#   - runtime output still observes the mutation;
#   - focused HIR uses a closure cell plus bare func_pointer;
#   - focused HIR does not materialize make_proc for this yield callback;
#   - the generated raw block function reads and writes the same closure cell.
#
# Exit semantics:
#   exit 0 — raw callback shape matches the current boundary.
#   exit 1 — shape or behavior regression.
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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/p1_raw_callback_probe.cr"
BIN="$TMPDIR/p1_raw_callback_probe"
RUN_LOG="$TMPDIR/run.log"
HIR_BASE="$TMPDIR/p1_raw_callback_probe_hir"
HIR="$HIR_BASE.hir"

cat > "$SRC" <<'EOF'
def each_once(&block : Int32 ->)
  yield 3
end

sum = 1
each_once do |x|
  sum += x
end
puts sum
EOF

fail() {
  echo "raw callback regression: $*" >&2
  exit 1
}

inconclusive() {
  echo "inconclusive: $*" >&2
  exit 2
}

extract_hir_func() {
  local symbol="$1"
  local src_file="$2"
  local dest_file="$3"

  awk -v symbol="$symbol" '
    $0 ~ "^func @" symbol "\\(" { in_body = 1 }
    in_body { print }
    in_body && $0 == "}" { exit }
  ' "$src_file" > "$dest_file"
}

"$COMPILER" "$SRC" -o "$BIN" >"$TMPDIR/compile.out" 2>"$TMPDIR/compile.err" ||
  inconclusive "failed to compile runtime probe ($(tail -20 "$TMPDIR/compile.err" | tr '\n' ' '))"

"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
RUN_RC=$?
if [[ $RUN_RC -ne 0 ]]; then
  fail "runtime probe failed with rc=$RUN_RC ($(tail -20 "$RUN_LOG" | tr '\n' ' '))"
fi

RUN_STDOUT=$(awk '
  /^=== STDOUT ===$/ { in_stdout = 1; next }
  /^=== STDERR ===$/ { in_stdout = 0 }
  in_stdout { print }
' "$RUN_LOG")

[[ "$RUN_STDOUT" == "4" ]] ||
  fail "runtime probe expected stdout 4, got $(printf '%q' "$RUN_STDOUT")"

CRYSTAL_V2_STOP_AFTER_HIR=1 "$COMPILER" "$SRC" --emit hir -o "$HIR_BASE" \
  >"$TMPDIR/hir.out" 2>"$TMPDIR/hir.err" ||
  inconclusive "failed to emit HIR ($(tail -20 "$TMPDIR/hir.err" | tr '\n' ' '))"

[[ -f "$HIR" ]] || inconclusive "missing HIR artifact: $HIR"

SUM_LINE=$(grep -n 'local "sum"' "$HIR" | head -1 | cut -d: -f1)
[[ -n "$SUM_LINE" ]] || fail "could not locate focused sum local in HIR"

FOCUSED_WINDOW="$TMPDIR/focused_raw_window.hir"
sed -n "${SUM_LINE},$((SUM_LINE + 20))p" "$HIR" > "$FOCUSED_WINDOW"

CELL_NAME=$(grep -Eo '__closure_cell_[0-9]+' "$FOCUSED_WINDOW" | head -1)
[[ -n "$CELL_NAME" ]] || fail "focused raw callback did not initialize a closure cell"

BLOCK_FN=$(grep -Eo '@__crystal_block_proc_[0-9]+' "$FOCUSED_WINDOW" | head -1 | cut -c2-)
[[ -n "$BLOCK_FN" ]] || fail "focused raw callback did not create a bare block function pointer"

grep -Eq "classvar_set __closure[.]@@$CELL_NAME" "$FOCUSED_WINDOW" ||
  fail "focused window does not write $CELL_NAME"

grep -Eq "func_pointer @$BLOCK_FN" "$FOCUSED_WINDOW" ||
  fail "focused window does not expose bare func_pointer for $BLOCK_FN"

if grep -Eq 'make_proc|make_closure' "$FOCUSED_WINDOW"; then
  fail "focused raw callback window materialized heap Proc env unexpectedly"
fi

BLOCK_BODY="$TMPDIR/raw_block_body.hir"
extract_hir_func "$BLOCK_FN" "$HIR" "$BLOCK_BODY"
[[ -s "$BLOCK_BODY" ]] || fail "missing HIR body for $BLOCK_FN"

grep -Eq "classvar_get __closure[.]@@$CELL_NAME" "$BLOCK_BODY" ||
  fail "$BLOCK_FN does not read $CELL_NAME"

grep -Eq "classvar_set __closure[.]@@$CELL_NAME" "$BLOCK_BODY" ||
  fail "$BLOCK_FN does not write $CELL_NAME"

if grep -Eq '@__closure_env|make_proc|make_closure' "$BLOCK_BODY"; then
  fail "$BLOCK_FN unexpectedly uses heap closure env machinery"
fi

echo "p1_raw_callback_shape_ok block_fn=$BLOCK_FN cell=$CELL_NAME"
