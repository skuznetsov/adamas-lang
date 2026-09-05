#!/usr/bin/env bash
# Regression coverage for root-qualified Pointer(T).null in a generated default.
#
# `::Pointer(self).null` inside a nested accessor expansion must use the
# Pointer-null intrinsic. The failing produced compiler left its normal call
# pending without a body, so the generated binary called the runtime stub.
# The relative spelling, Pointer(T).new(nonzero), and a
# user-defined namespaced Pointer(T) remain independent controls.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/absolute_pointer_null_default.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

failures=0

run_case() {
  local name="$1"
  local src="$TMP_DIR/$name.cr"
  local bin="$TMP_DIR/$name"
  local compile_log="$TMP_DIR/$name.compile.log"
  local run_log="$TMP_DIR/$name.run.log"

  cat >"$src"

  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 8192 \
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

run_case absolute_default <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

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

run_case relative_default <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

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
    property value : Pointer(self) = Pointer(self).null
  end
end

struct Probe
  include Link
end

p = Probe.new
LibC.exit(1) unless p.value.null?
LibC.exit(0)
CR

run_case nonzero_new_default <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

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
end

module Link
  macro included
    property value : ::Pointer(self) = ::Pointer(self).new(1_u64)
  end
end

struct Probe
  include Link
end

p = Probe.new
LibC.exit(1) unless p.value.address == 1_u64
LibC.exit(0)
CR

run_case user_namespaced_pointer <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Probe
end

module User
  struct Pointer(T)
    def self.null : UInt64
      7_u64
    end
  end
end

LibC.exit(1) unless ::User::Pointer(Probe).null == 7_u64
LibC.exit(0)
CR

if [[ $failures -ne 0 ]]; then
  echo "FAIL: $failures case(s)"
  exit 1
fi

echo "ok: absolute builtin Pointer(T).null default and controls"
