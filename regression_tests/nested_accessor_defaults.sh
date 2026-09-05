#!/usr/bin/env bash
# Regression coverage for defaults on typed accessors materialized from a
# nested `macro included` expansion.
#
# The expansion must retain the default expression and its arena, register the
# generated ivar/accessors, initialize the default before initialize runs, and
# let an explicit constructor assignment override it.  The final case mirrors
# Crystal's PointerLinkedList node shape and supplies the small primitive
# surface needed by a --no-prelude runtime.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested_accessor_defaults.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "compiler not found: $COMPILER" >&2
  exit 2
fi

failures=0

run_case() {
  local name="$1"
  local src="$TMP_DIR/$name.cr"
  local bin="$TMP_DIR/$name"
  local compile_log="$TMP_DIR/$name.compile.log"
  local run_log="$TMP_DIR/$name.run.log"

  cat >"$src"

  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
      "$src" --no-prelude -o "$bin" >"$compile_log" 2>&1; then
    echo "FAIL[$name]: compiler failed" >&2
    cat "$compile_log" >&2
    failures=$((failures + 1))
    return
  fi

  if ! "$ROOT_DIR/scripts/run_safe.sh" "$bin" 5 512 >"$run_log" 2>&1; then
    echo "FAIL[$name]: generated binary failed" >&2
    cat "$run_log" >&2
    failures=$((failures + 1))
    return
  fi

  if ! grep -Fq '[EXIT: 0]' "$run_log"; then
    echo "FAIL[$name]: expected [EXIT: 0]" >&2
    cat "$run_log" >&2
    failures=$((failures + 1))
    return
  fi

  echo "PASS[$name]"
}

expect_rejected() {
  local name="$1"
  local expected="$2"
  local src="$TMP_DIR/$name.cr"
  local compile_log="$TMP_DIR/$name.compile.log"
  local bin="$TMP_DIR/$name"

  cat >"$src"

  if "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
      "$src" --no-prelude -o "$bin" >"$compile_log" 2>&1; then
    echo "FAIL[$name]: unsupported nested accessor was accepted" >&2
    cat "$compile_log" >&2
    failures=$((failures + 1))
    return
  fi

  if ! grep -Fq "$expected" "$compile_log"; then
    echo "FAIL[$name]: wrong rejection signature" >&2
    cat "$compile_log" >&2
    failures=$((failures + 1))
    return
  fi

  echo "PASS[$name]: rejected"
}

run_case class_default <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Link
  macro included
    property count : Int32 = 42
  end
end

class Probe
  include Link
end

LibC.exit(Probe.new.count - 42)
CR

run_case class_explicit_override <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Link
  macro included
    property count : Int32 = 42
  end
end

class Probe
  include Link

  def initialize(@count : Int32 = 73)
  end
end

LibC.exit(Probe.new.count - 73)
CR

run_case struct_default <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Link
  macro included
    property count : Int32 = 42
  end
end

struct Probe
  include Link
end

LibC.exit(Probe.new.count - 42)
CR

run_case default_call <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def default_count : Int32
  42
end

module Link
  macro included
    property count : Int32 = default_count
  end
end

class Probe
  include Link
end

LibC.exit(Probe.new.count - 42)
CR

run_case pointer_self_default <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

# Minimal no-prelude declarations matching the primitive surface used by the
# original PointerLinkedList node.  The compiler lowers these primitives
# intrinsically; the declarations avoid an unresolved method stub at runtime.
struct Pointer(T)
  @[Primitive(:pointer_new)]
  def self.new(address : UInt64) : self
  end

  def self.null : self
    self.new(0_u64)
  end

  @[Primitive(:pointer_address)]
  def address : UInt64
  end

  def null? : Bool
    address == 0_u64
  end
end

module Link
  macro included
    property previous : ::Pointer(self) = ::Pointer(self).null
    property next : ::Pointer(self) = ::Pointer(self).null
    # This extra nonzero value makes the pointer default observable instead of
    # allowing zero-filled allocation to satisfy the whole case.
    property marker : ::Pointer(self) = ::Pointer(self).new(1_u64)
  end
end

struct Probe
  include Link
end

p = Probe.new
LibC.exit(1) unless p.previous.null?
LibC.exit(2) unless p.next.null?
LibC.exit(3) unless p.marker.address == 1_u64
LibC.exit(0)
CR

expect_rejected untyped_guard 'unsupported nested accessor macro output' <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Link
  macro included
    getter value
  end
end

class Probe
  include Link
end

LibC.exit(0)
CR

expect_rejected bang_guard 'unsupported nested accessor macro output' <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Link
  macro included
    getter! value : Int32
  end
end

class Probe
  include Link
end

LibC.exit(0)
CR

if [[ "$failures" -eq 0 ]]; then
  echo "nested_accessor_defaults_ok"
  exit 0
fi

echo "nested_accessor_defaults_failed: $failures case(s)" >&2
exit 1
