#!/usr/bin/env bash
# Original-first checks for integer source autocasts when a call carries a
# literal block. HIR-level contract coverage lives in the source-call specs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
[[ -x "$SAFE_RUNNER" && -n "$ORIGINAL" && -x "$ORIGINAL" ]] || {
  echo "installed Crystal or SAFE runner is unavailable" >&2
  exit 2
}
if [[ "$ORIGINAL_ONLY" != 1 && ! -x "$COMPILER" ]]; then
  echo "candidate compiler is unavailable" >&2
  exit 2
fi

if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
else
  CRYSTAL_STDLIB="$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$ORIGINAL" 10 512 env CRYSTAL_PATH)"
fi
stdlib_found=0
IFS=: read -r -a stdlib_paths <<<"$CRYSTAL_STDLIB"
for stdlib_entry in "${stdlib_paths[@]}"; do
  if [[ -d "$stdlib_entry" ]]; then
    stdlib_found=1
    break
  fi
done
[[ "$stdlib_found" == 1 ]] || { echo "installed Crystal stdlib is unavailable" >&2; exit 2; }

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/source-integer-block-autocast.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache.*
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/positive.cr" <<'CRYSTAL'
@[Link("c")]
lib SourceIntegerBlockAutocastC
  fun putchar(value : Int32) : Int32
end

class SourceIntegerBlockAutocastSink
  def self.observe(value : UInt8)
    SourceIntegerBlockAutocastC.putchar(85) # U
  end

  def self.observe(value : UInt16)
    SourceIntegerBlockAutocastC.putchar(86) # V
  end

  def self.observe(value : Int16)
    SourceIntegerBlockAutocastC.putchar(87) # W
  end
end

def source_integer_top_level(value : UInt8, &block : -> Int32) : UInt8
  yield
  value
end

class SourceIntegerBlockAutocast
  def self.positional(value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end

  def positional_instance(value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end

  def self.named(*, value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end

  def self.byte_source : UInt8
    65_u8
  end

  # This checks a safe runtime widening in a block-bearing source call.
  def self.widen(value : Int16, &block : -> Int32) : Int16
    yield
    value
  end

  def self.bare_class_call : UInt8
    positional(65) { SourceIntegerBlockAutocastC.putchar(98) }
  end
end

# Same UInt8 argument restriction, with the block overload first.
class SourceIntegerBlockFirst
  def self.pick(value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end

  def self.pick(value : UInt8) : UInt16
    65_u16
  end
end

# Same overloads in the opposite declaration order.
class SourceIntegerNoBlockFirst
  def self.pick(value : UInt8) : UInt16
    65_u16
  end

  def self.pick(value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end
end

# The block-bearing UInt8 overload must beat a no-block UInt16 overload only
# when a block is present.
class SourceIntegerDifferentRestriction
  def self.pick(value : UInt16) : UInt16
    value
  end

  def self.pick(value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end
end

SourceIntegerBlockAutocastSink.observe(
  source_integer_top_level(65) { SourceIntegerBlockAutocastC.putchar(97) }
)
SourceIntegerBlockAutocastSink.observe(SourceIntegerBlockAutocast.bare_class_call)
SourceIntegerBlockAutocastSink.observe(
  SourceIntegerBlockAutocast.positional(65) { SourceIntegerBlockAutocastC.putchar(99) }
)
instance = SourceIntegerBlockAutocast.new
SourceIntegerBlockAutocastSink.observe(
  instance.positional_instance(65) { SourceIntegerBlockAutocastC.putchar(100) }
)
SourceIntegerBlockAutocastSink.observe(
  SourceIntegerBlockAutocast.named(value: 65) { SourceIntegerBlockAutocastC.putchar(101) }
)
byte = SourceIntegerBlockAutocast.byte_source
SourceIntegerBlockAutocastSink.observe(
  SourceIntegerBlockAutocast.widen(byte) { SourceIntegerBlockAutocastC.putchar(102) }
)

# Exercise both block/no-block call shapes repeatedly, with opposite warm-up
# order for the two declaration orders.
SourceIntegerBlockAutocastSink.observe(SourceIntegerBlockFirst.pick(65))
SourceIntegerBlockAutocastSink.observe(
  SourceIntegerBlockFirst.pick(65) { SourceIntegerBlockAutocastC.putchar(103) }
)
SourceIntegerBlockAutocastSink.observe(SourceIntegerBlockFirst.pick(65))
SourceIntegerBlockAutocastSink.observe(
  SourceIntegerBlockFirst.pick(65) { SourceIntegerBlockAutocastC.putchar(104) }
)

SourceIntegerBlockAutocastSink.observe(
  SourceIntegerNoBlockFirst.pick(65) { SourceIntegerBlockAutocastC.putchar(105) }
)
SourceIntegerBlockAutocastSink.observe(SourceIntegerNoBlockFirst.pick(65))
SourceIntegerBlockAutocastSink.observe(
  SourceIntegerNoBlockFirst.pick(65) { SourceIntegerBlockAutocastC.putchar(106) }
)
SourceIntegerBlockAutocastSink.observe(SourceIntegerNoBlockFirst.pick(65))

SourceIntegerBlockAutocastSink.observe(SourceIntegerDifferentRestriction.pick(65))
SourceIntegerBlockAutocastSink.observe(
  SourceIntegerDifferentRestriction.pick(65) { SourceIntegerBlockAutocastC.putchar(107) }
)
SourceIntegerBlockAutocastSink.observe(SourceIntegerDifferentRestriction.pick(65))
SourceIntegerBlockAutocastSink.observe(
  SourceIntegerDifferentRestriction.pick(65) { SourceIntegerBlockAutocastC.putchar(108) }
)
SourceIntegerBlockAutocastC.putchar(10)
CRYSTAL
printf 'aUbUcUdUeUfWVgUVhUiUVjUVVkUVlU\n' >"$WORK_DIR/positive.expected"

cat >"$WORK_DIR/reject_positional_large_literal.cr" <<'CRYSTAL'
class RejectBlockAutocastPositionalLarge
  def self.take(value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end

  def self.run
    take(300) { 0 }
  end
end

RejectBlockAutocastPositionalLarge.run
CRYSTAL

cat >"$WORK_DIR/reject_named_large_literal.cr" <<'CRYSTAL'
class RejectBlockAutocastNamedLarge
  def self.take(*, value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end

  def self.run
    take(value: 300) { 0 }
  end
end

RejectBlockAutocastNamedLarge.run
CRYSTAL

cat >"$WORK_DIR/reject_runtime_narrowing.cr" <<'CRYSTAL'
class RejectBlockAutocastRuntimeNarrowing
  def self.take(value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end

  def self.source : Int32
    65
  end

  def self.run
    take(source) { 0 }
  end
end

RejectBlockAutocastRuntimeNarrowing.run
CRYSTAL

cat >"$WORK_DIR/reject_missing_block.cr" <<'CRYSTAL'
class RejectBlockAutocastMissingBlock
  def self.take(value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end

  def self.run
    take(65)
  end
end

RejectBlockAutocastMissingBlock.run
CRYSTAL

cat >"$WORK_DIR/reject_missing_positional.cr" <<'CRYSTAL'
class RejectBlockAutocastMissingPositional
  def self.take(value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end

  def self.run
    take { 0 }
  end
end

RejectBlockAutocastMissingPositional.run
CRYSTAL

cat >"$WORK_DIR/reject_extra_positional.cr" <<'CRYSTAL'
class RejectBlockAutocastExtraPositional
  def self.take(value : UInt8, &block : -> Int32) : UInt8
    yield
    value
  end

  def self.run
    take(65, 66) { 0 }
  end
end

RejectBlockAutocastExtraPositional.run
CRYSTAL

cat >"$WORK_DIR/reject_block_forbidden.cr" <<'CRYSTAL'
class RejectBlockAutocastForbiddenBlock
  def self.take(value : UInt8) : UInt8
    value
  end

  def self.run
    take(65) { 0 }
  end
end

RejectBlockAutocastForbiddenBlock.run
CRYSTAL

ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)

compile_case() {
  local stage="$1" name="$2" status=0
  local -a command
  if [[ "$stage" == original ]]; then
    command=("$ORIGINAL" 180 8192 build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}")
  else
    command=("$COMPILER" 180 8192 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$name" ADAMAS_LLVM_CACHE=0 \
    "$SAFE_RUNNER" "${command[@]}" "$WORK_DIR/$name.cr" -o "$WORK_DIR/$stage.$name.bin" \
    >"$WORK_DIR/$stage.$name.compile.log" 2>&1 || status=$?
  return "$status"
}

check_positive() {
  local stage="$1"
  compile_case "$stage" positive || {
    cat "$WORK_DIR/$stage.positive.compile.log" >&2
    echo "FAIL[$stage/positive]: expected successful block-bearing source call compilation" >&2
    return 1
  }
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/$stage.positive.bin" 10 512 \
    >"$WORK_DIR/$stage.stdout" 2>"$WORK_DIR/$stage.run.log" || {
      cat "$WORK_DIR/$stage.run.log" >&2
      echo "FAIL[$stage/positive]: runtime failed" >&2
      return 1
    }
  diff -u "$WORK_DIR/positive.expected" "$WORK_DIR/$stage.stdout"
}

check_rejection() {
  local stage="$1" name="$2" expected_name="$3" expected_type="${4:-}" status=0
  compile_case "$stage" "$name" || status=$?
  if [[ "$status" != 1 || -e "$WORK_DIR/$stage.$name.bin" ]]; then
    cat "$WORK_DIR/$stage.$name.compile.log" >&2
    echo "FAIL[$stage/$name]: expected semantic rejection without an executable" >&2
    return 1
  fi
  python3 - "$WORK_DIR/$stage.$name.compile.log" "$expected_name" "$expected_type" <<'PY_REJECT'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(errors="replace").lower()
assert "error" in text, text
assert sys.argv[2].lower() in text, text
if sys.argv[3] == "integer-contract":
    assert "int32" in text, text
    assert "uint8" in text or "no overload matches" in text, text
elif sys.argv[3] == "block-contract":
    assert "block" in text or "no overload matches" in text, text
elif sys.argv[3] == "arity-contract":
    assert "argument" in text or "no overload matches" in text, text
for forbidden in ("syntax error", "parser errors", "internal compiler error", "unhandled exception"):
    assert forbidden not in text, text
PY_REJECT
}

negative_cases=(
  "reject_positional_large_literal:take:integer-contract"
  "reject_named_large_literal:take:integer-contract"
  "reject_runtime_narrowing:take:integer-contract"
  "reject_missing_block:take:block-contract"
  "reject_missing_positional:take:arity-contract"
  "reject_extra_positional:take:arity-contract"
  "reject_block_forbidden:take:block-contract"
)

# The candidate is gated on the full installed-Crystal result first.
check_positive original
for item in "${negative_cases[@]}"; do
  IFS=: read -r name expected_name expected_type <<<"$item"
  check_rejection original "$name" "$expected_name" "$expected_type"
done
if [[ "$ORIGINAL_ONLY" == 1 ]]; then
  echo "PASS[original]: block-bearing source integer autocast oracle"
  exit 0
fi

check_positive candidate
for item in "${negative_cases[@]}"; do
  IFS=: read -r name expected_name expected_type <<<"$item"
  check_rejection candidate "$name" "$expected_name" "$expected_type"
done

diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"
echo "PASS: block-bearing positional/named integer autocast, overload order, widening, and strict rejection"
