#!/usr/bin/env bash
# Runtime guard for constructor forwarding with a concrete optional tail.
#
# A generated bootstrap compiler once materialized the allocator with a
# String argument but forwarded that argument to the Nil specialization of
# initialize.  The initializer therefore observed nil and silently discarded
# the supplied value.  This reducer keeps the optional receiver last, passes a
# concrete String, and observes the initializer's result at runtime.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defnode_receiver_optional_tail.XXXXXX")"
cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "kept_tmp=$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
BUILD_LOG="$TMP_DIR/build.log"
RUN_LOG="$TMP_DIR/run.log"

cat >"$SRC" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

class Span
end

class Parameter
end

enum Visibility
  Public
  Private
  Protected
end

class ReceiverCarrier
  @marker : Int32

  # The two overloads are intentional: DefNode has Array(Parameter) and Nil
  # constructor variants before its nullable tail.  Keeping those variants in
  # the reducer exercises allocator overload selection instead of only the
  # single-constructor forwarding path.
  def initialize(
      span : Span,
      name : Slice(UInt8),
      params : Array(Parameter),
      return_type : Slice(UInt8)?,
      body : Array(Int32)?,
      is_abstract : Bool? = nil,
      visibility : Visibility? = nil,
      receiver : String? = nil
    )
    @marker = 0
    if receiver
      @marker = 42
    end
  end

  def initialize(
      span : Span,
      name : Slice(UInt8),
      params : Nil,
      return_type : Slice(UInt8)?,
      body : Array(Int32)?,
      is_abstract : Bool? = nil,
      visibility : Visibility? = nil,
      receiver : String? = nil
    )
    @marker = 0
    if receiver
      @marker = 84
    end
  end

  def marker : Int32
    @marker
  end
end

empty_slice = Slice.new(Pointer(UInt8).null, 0)
params = [Parameter.new]
carrier = ReceiverCarrier.new(Span.new, empty_slice, params, nil, nil, nil, nil, "self")
LibC.printf("%d\n", carrier.marker)
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
  "$SRC" --no-prelude -o "$OUT" >"$BUILD_LOG" 2>&1
compile_status=$?
set -e
if [[ $compile_status -ne 0 || ! -x "$OUT" ]]; then
  echo "defnode optional-tail guard: compiler failed (status=$compile_status)" >&2
  cat "$BUILD_LOG" >&2
  exit 2
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  echo "defnode optional-tail guard: produced binary failed (status=$run_status)" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

if ! grep -Fxq "42" "$RUN_LOG"; then
  echo "defnode optional-tail guard: concrete receiver was not preserved" >&2
  echo "expected output: 42" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "defnode_receiver_optional_tail_bootstrap_ok"
