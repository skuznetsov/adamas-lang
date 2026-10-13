#!/usr/bin/env bash
# A virtual included-forall call must expose the complete runtime return set
# before its result selects an enclosing overload.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/virtual_included_forall_return.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
  fun exit(status : Int32) : NoReturn
end

module VirtualForallFlow(T)
  def echo(value : T) : T forall T
    value
  end
end

class VirtualForallBase
  include VirtualForallFlow(UInt64)
end

class VirtualForallChild < VirtualForallBase
  def echo(value : Int32) : String
    "child"
  end
end

class VirtualForallInheritedChild < VirtualForallBase
end

class VirtualForallSameReturnChild < VirtualForallBase
  def echo(value : Int32) : Int32
    value + 1
  end
end

class VirtualForallOtherOverloadChild < VirtualForallBase
  def echo(value : String) : Int32
    99
  end
end

class VirtualForallNilChild < VirtualForallBase
  def echo(value : Int32) : Nil
    nil
  end
end

def tag(value : Int32) : Int32
  value == 42 ? 41 : (value == 43 ? 44 : 40)
end

def tag(value : String) : Int32
  value == "child" ? 42 : 39
end

def tag(value : Nil) : Int32
  45
end

def mixed_tag(value : Int32) : Int32
  value
end

def mixed_tag(value : String) : String
  value
end

def mixed_tag(value : Nil) : Nil
  nil
end

def classify_mixed(value : Int32) : Int32
  71
end

def classify_mixed(value : String) : Int32
  72
end

def classify_mixed(value : Nil) : Int32
  73
end

def fallback_tag(value : Int32) : Int32
  81
end

def fallback_tag(value) : Int32
  82
end

def union_formal_tag(value : Int32) : Int32
  91
end

def union_formal_tag(value : String | Nil) : Int32
  if value.nil?
    94
  else
    value.size == 5 ? 92 : 93
  end
end

def dispatch_argument_once : Int32
  LibC.printf("dispatch_argument_once\n")
  42
end

def route(owner : VirtualForallBase) : Int32
  tag(owner.echo(42))
end

def route_once(owner : VirtualForallBase) : Int32
  tag(owner.echo(dispatch_argument_once))
end

def route_mixed(owner : VirtualForallBase) : Int32
  classify_mixed(mixed_tag(owner.echo(42)))
end

def route_untyped_fallback(owner : VirtualForallBase) : Int32
  fallback_tag(owner.echo(42))
end

def route_union_formal(owner : VirtualForallBase) : Int32
  union_formal_tag(owner.echo(42))
end

def direct_child(owner : VirtualForallChild) : Int32
  tag(owner.echo(42))
end

def direct_same_return_child(owner : VirtualForallSameReturnChild) : Int32
  tag(owner.echo(42))
end

failures = 0
failures |= 1 unless route(VirtualForallBase.new) == 41
failures |= 2 unless route(VirtualForallInheritedChild.new) == 41
failures |= 4 unless route(VirtualForallChild.new) == 42
failures |= 8 unless route(VirtualForallSameReturnChild.new) == 44
failures |= 16 unless route(VirtualForallOtherOverloadChild.new) == 41
failures |= 32 unless route(VirtualForallNilChild.new) == 45
failures |= 64 unless direct_child(VirtualForallChild.new) == 42
failures |= 128 unless direct_same_return_child(VirtualForallSameReturnChild.new) == 44
failures |= 256 unless route_once(VirtualForallNilChild.new) == 45
failures |= 512 unless route_mixed(VirtualForallBase.new) == 71
failures |= 1024 unless route_mixed(VirtualForallChild.new) == 72
failures |= 2048 unless route_mixed(VirtualForallNilChild.new) == 73
failures |= 4096 unless route_untyped_fallback(VirtualForallBase.new) == 81
failures |= 8192 unless route_untyped_fallback(VirtualForallChild.new) == 82
failures |= 16384 unless route_untyped_fallback(VirtualForallNilChild.new) == 82
failures |= 32768 unless route_union_formal(VirtualForallBase.new) == 91
failures |= 65536 unless route_union_formal(VirtualForallChild.new) == 92
failures |= 131072 unless route_union_formal(VirtualForallNilChild.new) == 94
LibC.printf("virtual_forall_failures:%d\n", failures)
LibC.exit(failures == 0 ? 0 : 1)
CR
if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/build.resources" "$SAFE_RUN" "$COMPILER" 300 8192 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" \
    >"$WORK_DIR/build.log" 2>&1; then
  echo "virtual included-forall return union: compile failed" >&2
  tail -40 "$WORK_DIR/build.log" >&2
  exit 1
fi
RUN_SAFE_RESOURCE_FILE="$WORK_DIR/run.resources" \
  "$SAFE_RUN" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^virtual_forall_failures:0$' "$WORK_DIR/run.log" || \
   ! grep -q '^dispatch_argument_once$' "$WORK_DIR/run.log" || \
   [[ $(grep -c '^dispatch_argument_once$' "$WORK_DIR/run.log") -ne 1 ]] || \
   ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "virtual included-forall return union: wrong enclosing overload (want EXIT 0)" >&2
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo virtual_included_forall_return_union_repro_ok
