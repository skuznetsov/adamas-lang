#!/usr/bin/env bash
# Regression: an owned reference returned by a call, wrapped into a nilable union,
# and carried through a cross-block Phi must keep its payload alive until the
# consumer block takes ownership.
#
# Pre-fix, HIR->MIR cross-block ARC tracing treated Copy/Cast as transparent but
# not UnionWrap. In `arr = make_array` inside the `if` branch below, the HIR shape
# is:
#   make_array() -> Copy -> UnionWrap(Array(Int32) as Array(Int32)?) -> Phi -> Tuple
# The Phi marked the UnionWrap cross-block, but not the underlying owned call
# result. Per-block ARC cleanup then emitted `rc_dec(make_array_result)` before
# the merge block built the returned tuple, so the returned Array was freed before
# use. In the s3 frontier this manifested as a freed Array(ExprId) buffer inside
# `Parser#parse_rescue_sections` and later as a bogus ExprId pointer in
# `BeginNode.ensure_body`.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arc-unionwrap-cross-block.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_OUT="$TMP_DIR/compile.out"
COMPILE_ERR="$TMP_DIR/compile.err"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
def make_array
  Array(Int32).new(2) do |i|
    if i == 0
      4354
    else
      12
    end
  end
end

def make(flag : Bool) : Tuple(Nil, Nil, Array(Int32)?)
  arr = nil
  if flag
    arr = make_array
  end
  {nil, nil, arr}
end

result = make(true)[2]
if result
  puts result[0]
  puts result[1]
else
  puts 0
end
CR

if ! "$COMPILER" "$SRC" -o "$BIN" >"$COMPILE_OUT" 2>"$COMPILE_ERR"; then
  echo "FAIL: compile failed"
  tail -80 "$COMPILE_ERR"
  exit 2
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 10 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

stdout="$(awk '/^=== STDOUT ===/{flag=1;next}/^=== STDERR ===/{flag=0}flag' "$RUN_LOG" | tr -d '\r')"
expected=$'4354\n12'

if [[ $run_status -eq 0 && "$stdout" == "$expected" ]]; then
  echo "PASS: cross-block UnionWrap preserved owned Array payload"
  exit 0
fi

echo "FAIL: cross-block UnionWrap lost or freed owned Array payload"
echo "run_status: $run_status"
echo "expected stdout:"
printf '%s\n' "$expected"
echo "actual stdout:"
printf '%s\n' "$stdout"
echo "--- run log tail ---"
tail -80 "$RUN_LOG"
exit 1
