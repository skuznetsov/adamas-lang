#!/usr/bin/env bash
# A literal `Void` type argument on a generic receiver (`Pointer(Void).null`)
# went through the typeof-degradation normalizer, which maps Void to
# Pointer(Void), so the receiver became `Pointer(Pointer(Void))`. Calls with
# such an argument then mangled as `f$Pointer(Pointer(Void))` (STUB) and
# overload selection on `Void*` params picked the wrong def. In the bootstrap
# stage2 failed to find `Fiber::Stack#initialize(Void*, Int32)`.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/void_pointer_generic_receiver.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Stk
  @size = 0
  def initialize(p : Void*, b : Void*)
    @size = 5
  end
  def initialize(p : Void*, s : Int32)
    @size = s
  end
  def size; @size; end
end
def f(p : Void*, s : Int32); s; end
def g(p : Void*); 3; end
def g(p : UInt8*); 4; end
LibC.exit(1) unless f(Pointer(Void).null, 9) == 9
v = Pointer(Void).null
LibC.exit(2) unless f(v, 8) == 8
LibC.exit(3) unless Stk.new(Pointer(Void).null, 7).size == 7
LibC.exit(4) unless Stk.new(Pointer(Void).null, Pointer(Void).null).size == 5
LibC.exit(5) unless g(Pointer(Void).null) == 3
LibC.exit(6) unless g(Pointer(UInt8).null) == 4
LibC.exit(0)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo void_pointer_generic_receiver_repro_ok
