#!/usr/bin/env bash
# Regression: pointerof(local) where the local is an inline value aggregate
# (lib struct / tuple / StaticArray) promoted to a heap/slab Alloc because it
# escapes (returned). The backend gave such operands a `%rN.addr` spill slot
# and pointerof returned the SLOT address, so `memset(pointerof(s), ...)`
# overwrote the saved data pointer instead of the struct bytes. Seen in S2
# when `stat` in FileDescriptor.system_info escaped -> fstat clobbered slot.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/heap_struct_local_pointerof_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/pe.cr" <<'CR'
lib LibC
  struct S
    a : Int32
    b : Int32
  end
  fun memset(p : S*, c : Int32, n : UInt64) : Void*
  fun exit(code : Int32) : NoReturn
end

def mk : LibC::S
  s = uninitialized LibC::S
  s.a = 0
  s.b = 0
  LibC.memset(pointerof(s), 1, 8_u64)
  s
end

class Box
  def initialize(@s : LibC::S)
  end

  def s
    @s
  end
end

def boxed : Box
  s = uninitialized LibC::S
  s.a = 0
  s.b = 0
  LibC.memset(pointerof(s), 2, 8_u64)
  Box.new(s)
end

x = mk
b = boxed
code = 0
code |= 1 unless x.a == 0x01010101 && x.b == 0x01010101
code |= 2 unless b.s.a == 0x02020202 && b.s.b == 0x02020202
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/pe.cr" --no-prelude -o "$WORK_DIR/pe" >"$WORK_DIR/pe.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/pe.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/pe" 5 512 >"$WORK_DIR/pe.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/pe.run.log"; then
  echo "FAIL: pointerof of a heap-promoted struct local did not address its data" >&2
  cat "$WORK_DIR/pe.run.log" >&2
  exit 1
fi
echo "PASS: pointerof of heap-promoted value locals addresses the data"
