#!/usr/bin/env bash
# Regression: `Klass.new(...) { }` where `initialize` yields (bare `yield` or
# an untyped `&` slot) had no raw-callback contract for the allocator's
# initialize target. The non-inlined block carrier stayed a POINTER, the
# yield returned Void, and with an anonymous `&` slot the block param was
# typed as the receiver class (`x : Bar`, calling `Bar#+`), so the binary hit
# a STUB or read garbage. The allocator now forwards the callsite block
# contract to the initialize target, and the block-param inference treats an
# untyped `&` slot like bare `yield`.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yield_initialize_block_contract_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/yi.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class DefaultYield
  @kind : Int32
  def initialize(x : Int32 = 3)
    @kind = yield x
  end
  def kind
    @kind
  end
end

class ArgYield
  @kind : Int32
  def initialize(x : Int32)
    @kind = yield x
  end
  def kind
    @kind
  end
end

class AnonSlotYield
  @kind : Int32
  def initialize(x : Int32 = 3, &)
    @kind = yield x
  end
  def kind
    @kind
  end
end

class TypedCall
  @kind : Int32
  def initialize(x : Int32, &blk : Int32 -> Int32)
    @kind = blk.call(x)
  end
  def kind
    @kind
  end
end

code = 0
code |= 1 unless DefaultYield.new { |x| x + 1 }.kind == 4
code |= 2 unless ArgYield.new(3) { |x| x + 1 }.kind == 4
code |= 4 unless AnonSlotYield.new { |x| x + 1 }.kind == 4
code |= 8 unless TypedCall.new(3) { |x| x + 1 }.kind == 4
LibC.exit(code)
CR

for inline_mode in on off; do
  if [ "$inline_mode" = off ]; then export ADAMAS_DISABLE_INLINE_YIELD=1; else unset ADAMAS_DISABLE_INLINE_YIELD; fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
      "$WORK_DIR/yi.cr" --no-prelude -o "$WORK_DIR/yi_$inline_mode" >"$WORK_DIR/yi_$inline_mode.build.log" 2>&1; then
    echo "FAIL: compile failed (inline yield $inline_mode)" >&2
    tail -20 "$WORK_DIR/yi_$inline_mode.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/yi_$inline_mode" 5 512 >"$WORK_DIR/yi_$inline_mode.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/yi_$inline_mode.run.log"; then
    echo "FAIL: yielding initialize block contract (inline yield $inline_mode)" >&2
    cat "$WORK_DIR/yi_$inline_mode.run.log" >&2
    exit 1
  fi
done
echo "PASS: yielding initialize gets the callsite block contract"
