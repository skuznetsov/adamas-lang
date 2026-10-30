#!/usr/bin/env bash
# Original-first native regression for tuple-call result inference through
# nested yields and block-local multiple assignment. No process is forked.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
if [[ "$ORIGINAL" != */* ]]; then
  ORIGINAL="$(command -v "$ORIGINAL" || true)"
fi
CRYSTAL_STDLIB="${CRYSTAL_PATH:-}"
if [[ -z "$CRYSTAL_STDLIB" && -x "$ORIGINAL" ]]; then
  CRYSTAL_STDLIB="$("$ORIGINAL" env CRYSTAL_PATH 2>/dev/null || true)"
fi
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-180}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"

[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "candidate, original Crystal, SAFE runner, or installed Crystal stdlib is unavailable" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/multiple-assign-local-result.XXXXXX")"
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$WORK_DIR"/cache.*
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/support.cr" <<'CRYSTAL'
@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end

module TupleCallFlow
  def self.pair(first : Int32, second : Int64) : Tuple(Int32, Int64)
    {first, second}
  end

  def self.nullable_pair(first : Int32?) : Tuple(Int32 | Nil, Int64)
    {first, 76_i64}
  end

  def self.yield_pair : Tuple(Int32, Int64)
    yield
  end

  def self.yield_pair_twice : Tuple(Int32, Int64)
    yield_pair { yield }
  end

  def self.bool_pair : Tuple(Bool, Int64)
    {true, 77_i64}
  end

  def self.with_number
    yield 78_i32
  end
end

class Int32Sink
  def self.consume(value : Int32)
    LibC.putchar(value)
  end
end

class Int64Sink
  def self.consume(value : Int64)
    LibC.putchar(76) # 'L'
  end
end

class BoolSink
  def self.consume(value : Bool)
    if value
      LibC.putchar(84) # 'T'
    else
      LibC.putchar(70) # 'F'
    end
  end
end

class NullableInt32Sink
  def self.observe(value : Int32?)
    if value
      LibC.putchar(value)
    else
      LibC.putchar(78) # 'N'
    end
  end
end
CRYSTAL

cat >"$WORK_DIR/positive.cr" <<'CRYSTAL'
require "./support"

# Direct tuple call: slot types remain distinct.
first, second = TupleCallFlow.pair(65_i32, 1_i64)
Int32Sink.consume(first)
Int64Sink.consume(second)

# One and two yield-forwarding layers preserve both positional slots.
first, second = TupleCallFlow.yield_pair { TupleCallFlow.pair(66_i32, 2_i64) }
Int32Sink.consume(first)
Int64Sink.consume(second)

first, second = TupleCallFlow.yield_pair_twice { TupleCallFlow.pair(67_i32, 3_i64) }
Int32Sink.consume(first)
Int64Sink.consume(second)

# Both outcomes of a nullable first slot are observed; the second remains Int64.
first, second = TupleCallFlow.nullable_pair(nil)
NullableInt32Sink.observe(first)
Int64Sink.consume(second)
first, second = TupleCallFlow.nullable_pair(68_i32)
NullableInt32Sink.observe(first)
Int64Sink.consume(second)

# A tuple call writes into a captured outer local from a yielding block.
captured = 0_i32
TupleCallFlow.with_number do |ignored|
  captured, captured_second = TupleCallFlow.pair(69_i32, 4_i64)
  Int64Sink.consume(captured_second)
end
Int32Sink.consume(captured)

# The block parameter shadows the outer Int32 local. Its Bool tuple assignment
# stays block-local, while the outer value keeps its original Int32 type/value.
shadowed = 70_i32
TupleCallFlow.with_number do |shadowed|
  shadowed, second = TupleCallFlow.bool_pair
  BoolSink.consume(shadowed)
  Int64Sink.consume(second)
end
Int32Sink.consume(shadowed)
LibC.putchar(10)
CRYSTAL
printf 'ALBLCLNLDLLETLF\n' >"$WORK_DIR/positive.expected"

cat >"$WORK_DIR/reject_nilable_slot_to_int32.cr" <<'CRYSTAL'
require "./support"

first, second = TupleCallFlow.nullable_pair(nil)
Int32Sink.consume(first)
CRYSTAL

ORIGINAL_LINK_ARGS=()
ADAMAS_LINK_ENV=()
if [[ "$(uname -s)" == Darwin ]]; then
  ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
  ADAMAS_LINK_ENV=(ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}")
fi

compile_case() {
  local stage="$1" name="$2" status=0
  local source="$WORK_DIR/$name.cr"
  local output="$WORK_DIR/$stage.$name.bin"
  local log="$WORK_DIR/$stage.$name.compile.log"
  local cache="$WORK_DIR/cache.$stage.$name"

  if [[ "$stage" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.$name.compile.resources" \
      "$SAFE_RUNNER" "$ORIGINAL" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}" \
      "$source" -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 "${ADAMAS_LINK_ENV[@]}" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.$name.compile.resources" \
      "$SAFE_RUNNER" "$COMPILER" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  return "$status"
}

run_positive() {
  local stage="$1"
  local output="$WORK_DIR/$stage.positive.bin"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.positive.run.resources" \
    "$SAFE_RUNNER" "$output" 10 512 >"$WORK_DIR/$stage.positive.stdout" \
    2>"$WORK_DIR/$stage.positive.run.log"; then
    echo "FAIL[$stage/positive]: runtime failed" >&2
    cat "$WORK_DIR/$stage.positive.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$stage.positive.run.log" || {
    cat "$WORK_DIR/$stage.positive.run.log" >&2
    return 1
  }
  diff -u "$WORK_DIR/positive.expected" "$WORK_DIR/$stage.positive.stdout"
}

reject_nilable_slot_to_int32() {
  local stage="$1" status=0
  local output="$WORK_DIR/$stage.reject_nilable_slot_to_int32.bin"
  if compile_case "$stage" reject_nilable_slot_to_int32; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -ne 1 || -e "$output" ]]; then
    echo "FAIL[$stage/reject_nilable_slot_to_int32]: expected a semantic Nil-to-Int32 rejection" >&2
    cat "$WORK_DIR/$stage.reject_nilable_slot_to_int32.compile.log" >&2
    return 1
  fi
  python3 - "$WORK_DIR/$stage.reject_nilable_slot_to_int32.compile.log" <<'PY_REJECT'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(errors="replace").lower()
assert "nil" in text and "int32sink" in text, text
assert "int32" in text and ("no overload matches" in text or "expect" in text), text
for forbidden in ("syntax error", "parser errors", "internal compiler error", "bug:"):
    assert forbidden not in text, text
assert "error" in text, text
PY_REJECT
}

# Qualify every source shape against Crystal before using Adamas as the
# candidate. This prevents a parser or fixture mistake from masquerading as a
# compiler regression.
if ! compile_case original positive; then
  echo "FAIL[original/positive]: compile failed" >&2
  cat "$WORK_DIR/original.positive.compile.log" >&2
  exit 1
fi
run_positive original
reject_nilable_slot_to_int32 original

if ! compile_case adamas positive; then
  echo "FAIL[adamas/positive]: compile failed" >&2
  cat "$WORK_DIR/adamas.positive.compile.log" >&2
  exit 1
fi
run_positive adamas
reject_nilable_slot_to_int32 adamas
echo "PASS: direct/one-yield/two-yield tuple slots, nullable outcomes, captured and shadowed locals, and strict Nil rejection"
