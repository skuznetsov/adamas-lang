#!/usr/bin/env bash
# Regression: a nil-annotated block contract (`& : T ->`) must NOT force the
# materialized block proc to return nil when the callee CONSUMES the yield
# value.
#
# `[1,2,3].index { |v| v == 2 }` is skipped by the inline-yield guard
# (callee has yield+return), so the block goes through the proc route.
# The callee's yield ABI comes from the callsite-recorded `__block_return__`
# (infer_yield_return_type does not trust the Nil annotation for `yield`),
# i.e. Bool here — but LM-657's caller-side force made the proc return nil.
# The two sides desynced: `yield` read garbage instead of the predicate and
# `index` matched at position 0.
#
# The force stays for callees WITHOUT yield (block.call route), where the
# call really is typed from the annotation-derived Proc param — that is the
# original LM-657 ABI crash (p2_nil_return_block_proc_no_prelude.sh guards it).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yield_nil_annot.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"

cat > "$SRC" <<'CR'
# stdlib route: Indexable#index(offset, & : T ->) consumes `yield v` in an if.
puts [1,2,3].index { |v| v == 2 } || -1
puts [1,2,3].index { |v| v == 9 } || -1
# no-yield sibling (block.call route) must keep the LM-657 nil contract alive.
def store_and_call(&block : Int32 ->) : Nil
  block.call(7)
end
store_and_call { |x| x + 100 }
puts "done"
# plain nil-contract yield consumer where the value is ignored — stays healthy.
def each_nilcontract(& : Int32 ->)
  yield 41
  yield 42
end
each_nilcontract { |v| puts v }
CR

"$COMPILER" "$SRC" -o "$OUT" >"$LOG" 2>&1 || {
  echo "COMPILE FAILED"
  tail -20 "$LOG"
  exit 1
}

ACTUAL="$("$RUN_SAFE" "$OUT" 10 512 2>/dev/null | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
EXPECTED=$'1\n-1\ndone\n41\n42'

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "MISMATCH"
  echo "--- expected ---"
  echo "$EXPECTED"
  echo "--- actual ---"
  echo "$ACTUAL"
  exit 1
fi

echo "OK: nil-annotated block procs keep the value for yield-consuming callees"
