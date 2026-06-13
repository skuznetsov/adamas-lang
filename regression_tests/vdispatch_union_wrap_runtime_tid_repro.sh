#!/usr/bin/env bash
# Regression test for shared-generic vdispatch union wrap corruption.
#
# Before fix: `Array(Nil|String)#[]?` routes through the SHARED
# `Indexable(T)#fetch`, whose return type is a wide mega-union over all
# Indexable(T) element types reached by RTA. generate_vdispatch_body
# typed every per-branch call result as the WRAPPER's mega-union return
# type, so the backend saw a degraded value type (generic Pointer) for
# bare-ptr callee results and stamped a STATIC discriminator picked as
# "first variant with a matching LLVM type" — e.g. type_id 433
# (Float::Printer::CachedPowers::Power) onto a String payload. Any
# narrowed method call on the fetched element then vdispatched to the
# wrong type's method (STUB CALLED: ...Power#empty? / in stage2: garbage
# 32-bit-truncated String pointer crash in track_enum_value).
#
# Fix (hir_to_mir.cr generate_vdispatch_body): type each branch call
# with the CALLEE's return type and emit an explicit UnionWrap into the
# dispatch union. The phi stays union-typed, and emit_union_wrap's
# runtime header read stamps the correct global type id for ptr payloads
# (header word == union discriminator == global type_ref.id; Nil = 0).
# Backed by llvm_backend.cr hardening: ptr→union wraps at slot-store,
# call-arg coercion, and Cast sites read the object header at runtime
# (emit_runtime_header_tid) instead of guessing a static variant, when
# every non-nil variant is header-backed (reference/array).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vdispatch_union_wrap.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_OUT="$TMP_DIR/compile.out"
COMPILE_ERR="$TMP_DIR/compile.err"
RUN_OUT="$TMP_DIR/run.out"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
# Array(Nil|String)#[]? goes through shared Indexable(T)#fetch whose
# return is a wide mega-union; the wrapped element's discriminator must
# reflect the runtime object (String / Nil), not a static guess.
arr = [] of Nil | String
arr << "hello"
arr << nil
arr << "world"
idx = 0
while idx < arr.size
  if s = arr[idx]?
    STDERR.puts s.empty? ? "(empty)" : s
  else
    STDERR.puts "(nil)"
  end
  idx += 1
end
STDERR.puts "done"
CR

set +e
"$COMPILER" "$SRC" -o "$BIN" >"$COMPILE_OUT" 2>"$COMPILE_ERR"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "compile failed"
  echo "compiler: $COMPILER"
  echo "status: $compile_status"
  echo "tmp_dir: $TMP_DIR"
  echo "--- stderr ---"
  cat "$COMPILE_ERR"
  echo "--- stdout ---"
  cat "$COMPILE_OUT"
  exit 2
fi

./scripts/run_safe.sh "$BIN" 5 256 >"$RUN_OUT"
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stderr:"
printf '%s\n' "$stderr_text"

expected=$'hello\n(nil)\nworld\ndone'

if [[ "$stderr_text" == "$expected" ]]; then
  echo "fixed: vdispatch branch results wrapped with runtime header type id"
  exit 0
fi

echo "unexpected output (expected: hello, (nil), world, done)"
cat "$RUN_OUT"
exit 1
