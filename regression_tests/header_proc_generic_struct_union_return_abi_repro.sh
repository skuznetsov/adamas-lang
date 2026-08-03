#!/usr/bin/env bash
# Runtime oracle for a generic struct receiver union whose concrete getter
# returns either a runtime-header-backed record or a raw Proc pointer.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/header_proc_generic_struct_union_return.XXXXXX")"

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"

cat >"$SRC" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

record HandlerProbe, value : Int32, block : Proc(Int32, Int32)

struct EntryProbe(V)
  getter value : V

  def initialize(@value : V)
  end
end

alias EntryUnion = EntryProbe(HandlerProbe) | EntryProbe(Proc(Int32, Int32))

def entry_value(entry : EntryUnion)
  entry.value
end

def make_handler_result
  offset = 1
  handler = HandlerProbe.new(17, ->(value : Int32) { value + offset })
  entry_value(EntryProbe(HandlerProbe).new(handler))
end

def make_proc_result
  factor = 3
  entry_value(EntryProbe(Proc(Int32, Int32)).new(->(value : Int32) { value * factor }))
end

handler_result = make_handler_result
handler_ok = case handler_result
             when HandlerProbe
               handler_result.value == 17 && handler_result.block.call(4) == 5
             when Proc(Int32, Int32)
               false
             end

proc_result = make_proc_result
proc_ok = case proc_result
          when HandlerProbe
            false
          when Proc(Int32, Int32)
            proc_result.call(7) == 21
          end

LibC.printf(handler_ok && proc_ok ? "OK\n" : "BAD\n")
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 4096 "$SRC" -o "$OUT" >"$TMP_DIR/compile.log" 2>&1; then
  echo "FAIL: compile error" >&2
  tail -20 "$TMP_DIR/compile.log" >&2
  exit 1
fi

RAW="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null)"
GOT="$(printf '%s\n' "$RAW" | sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/p' | sed '1d;$d')"

if [[ "$GOT" != "OK" ]]; then
  echo "FAIL: header/Proc generic struct union return ABI (expected 'OK', got '$GOT')" >&2
  exit 1
fi

echo "PASS: explicit branch wraps preserve header-backed records and raw Proc values"
