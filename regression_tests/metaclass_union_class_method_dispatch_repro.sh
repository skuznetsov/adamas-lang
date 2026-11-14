#!/usr/bin/env bash
# Regression: a call on a metaclass-union receiver (every arm a type object,
# e.g. `k = cond ? M : N`, or Int.from_io's `format : IO::ByteFormat` holding
# LittleEndian | BigEndian) must run the class-side method of the arm held at
# runtime. Source type-literal facts made the receiver take the static
# class-method path with the union spelling as owner, so the call resolved to
# no body (`Int32.from_io$...BF::BE.class | BF::LE.class` returned Void).
# Covered: module arms, mixed result types, an abstract-struct arm inheriting
# its class method, type-literal arguments keeping their kind inside each arm,
# and the from_io shape. Class-only unions are a known open gap (header-less
# class objects share the instance carrier) and are not claimed here.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-metaclass-union-class-method-dispatch.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > module_arms.cr <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

module M
  def self.make(x : Int32) : Int32
    x &+ 1
  end
end

module N
  def self.make(x : Int32) : Int32
    x &+ 2
  end
end

def pick(x : Int32)
  x > 0 ? M : N
end

def run(k, v : Int32) : Int32
  k.make(v)
end

LibC.exit(run(pick(1), 10) &+ run(pick(-1), 0))
CR

cat > mixed_result_types.cr <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

module M
  def self.make(x : Int32) : Int32
    x &+ 1
  end
end

module N
  def self.make(x : Int32) : Int64
    x.to_i64 &+ 2
  end
end

def pick(x : Int32)
  x > 0 ? M : N
end

def run(k, v : Int32)
  k.make(v)
end

a = run(pick(1), 10)
b = run(pick(-1), 0)
ra = a.is_a?(Int32) ? a : 50
rb = b.is_a?(Int64) ? b.to_i32 : 60
LibC.exit(ra &+ rb)
CR

cat > struct_and_module_arms.cr <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

abstract struct Base
  def self.make(x : Int32) : Int32
    x &+ 100
  end
end

struct S1 < Base
end

struct S2 < Base
  def self.make(x : Int32) : Int32
    x &+ 2
  end
end

module Q
  def self.make(x : Int32) : Int32
    x &+ 3
  end
end

def pick(x : Int32)
  if x > 0
    S1
  elsif x == 0
    S2
  else
    Q
  end
end

def run(k, v : Int32) : Int32
  k.make(v)
end

LibC.exit(run(pick(1), 1) &- 100 &+ run(pick(0), 10) &+ run(pick(-1), 20))
CR

cat > type_literal_arguments.cr <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

module M
  def self.tag(t) : Int32
    t.is_a?(Int32.class) ? 1 : 2
  end
end

module N
  def self.tag(t) : Int32
    t.is_a?(Int32.class) ? 3 : 4
  end
end

def pick(x : Int32)
  x > 0 ? M : N
end

def run(k) : Int32
  k.tag(Int32) &* 10 &+ k.tag(Int64)
end

LibC.exit(run(pick(1)) &+ run(pick(-1)))
CR

cat > from_io_byte_format.cr <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

class Src
  def initialize(@v : Int32)
  end

  def get : Int32
    @v
  end
end

module BF
  abstract def decode(int : Int32.class, io : Src)
  abstract def decode(int : Int64.class, io : Src)

  def decode(type : Float32.class, io : Src) : Float32
    1.5_f32
  end

  module LE
    extend BF
  end

  module BE
    extend BF
  end

  {% for mod in %w(LE BE) %}
    module {{mod.id}}
      {% for type, i in %w(Int32 Int64) %}
        def self.decode(int : {{type.id}}.class, io : Src)
          {% if mod == "LE" %}
            io.get.to_{{ type == "Int32" ? "i32".id : "i64".id }}
          {% else %}
            (io.get &+ 1).to_{{ type == "Int32" ? "i32".id : "i64".id }}
          {% end %}
        end
      {% end %}
    end
  {% end %}
end

struct Int32
  def self.from_io(io : Src, format : BF) : self
    format.decode(self, io)
  end
end

def pick(x : Int32)
  x > 0 ? BF::LE : BF::BE
end

f = pick(1)
r = Int32.from_io(Src.new(14), f)
g = pick(-1)
r2 = Int32.from_io(Src.new(14), g)
LibC.exit(r + r2 - 14)
CR

exit_code() {
  local out
  out="$("$safe" "$1" 5 256 2>&1 || true)"
  printf '%s\n' "$out" | sed -n 's/^\[EXIT: \([0-9-]*\)\].*/\1/p' | tail -1
}

fail=0
check() {
  local case_name="$1" want="$2" got_original got_candidate
  "$safe" "$original" 120 4096 build "$case_name.cr" --prelude=empty --single-module \
    --no-debug "${original_flags[@]}" -o "$case_name.original" > "$case_name.original.log" 2>&1 ||
    { cat "$case_name.original.log" >&2; echo "ORACLE_BUILD_FAIL $case_name"; fail=1; return; }
  got_original="$(exit_code "$work/$case_name.original")"
  if [[ "$got_original" != "$want" ]]; then
    echo "ORACLE_MISMATCH $case_name: original=$got_original expected=$want"; fail=1; return
  fi
  if ! "$safe" "$candidate" 120 4096 "$case_name.cr" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$case_name.candidate" > "$case_name.candidate.log" 2>&1; then
    echo "FAIL $case_name: candidate compile failed"
    grep -a -m3 -i error "$case_name.candidate.log" || true
    fail=1; return
  fi
  got_candidate="$(exit_code "$work/$case_name.candidate")"
  if [[ "$got_candidate" != "$want" ]]; then
    echo "FAIL $case_name: candidate=$got_candidate expected=$want"; fail=1; return
  fi
  echo "ok $case_name"
}

check module_arms 13
check mixed_result_types 13
check struct_and_module_arms 36
check type_literal_arguments 46
check from_io_byte_format 15

[[ $fail == 0 ]] || exit 1
printf 'PASS metaclass union class method dispatch\n'
