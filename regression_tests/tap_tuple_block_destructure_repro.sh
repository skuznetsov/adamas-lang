#!/usr/bin/env bash
# Object#tap yields one tuple value; multiple block parameters must destructure
# that tuple instead of all aliasing the original receiver.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tap_tuple_block_destructure.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Reader
end

class Writer
  @@calls = 0

  def close_on_finalize=(value : Bool) : Bool
    @@calls += 1
    value
  end

  def self.calls : Int32
    @@calls
  end
end

class WholeReceiverProbe
  @@calls = 0

  def self.capture(value : Tuple(Reader, Writer)) : Nil
    @@calls += 1
  end

  def self.calls : Int32
    @@calls
  end
end

class Object
  def tap(&)
    yield self
    self
  end
end

pair = {Reader.new, Writer.new}
pair.tap do |reader, writer|
  writer.close_on_finalize = false
end

triple = {Reader.new, Writer.new, 42}
triple.tap do |reader, writer|
  writer.close_on_finalize = false
end

pair.tap do |whole|
  WholeReceiverProbe.capture(whole)
end

LibC.exit(Writer.calls == 2 && WholeReceiverProbe.calls == 1 ? 0 : 1)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" \
    >"$WORK_DIR/build.log" 2>&1; then
  echo "tap tuple block destructure: compile failed" >&2
  tail -30 "$WORK_DIR/build.log" >&2
  exit 1
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 \
    >"$WORK_DIR/run.log" 2>&1; then
  echo "tap tuple block destructure: runtime failed" >&2
  grep -E '^(STUB CALLED:|\[EXIT|\[TIMEOUT|\[KILLED)' "$WORK_DIR/run.log" >&2 ||
    cat "$WORK_DIR/run.log" >&2
  exit 1
fi

if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "tap tuple block destructure: expected aggregate check to exit 0:" >&2
  grep -E '^\[EXIT' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi

echo tap_tuple_block_destructure_repro_ok
