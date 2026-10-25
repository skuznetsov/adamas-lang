#!/usr/bin/env bash
# Materializing `Lst(Rx(Int32))` from a method body registers `Rx(Int32)` while
# the argument `Rx(Int32)` is still on the generic-argument recursion guard.
# The included `property previous : ::Pointer(self)` then named `Rx(Int32)`
# again, hit the guard, and stored `@previous : Pointer(Void)`, so
# `Lst#delete` failed with "no overload matches Lst(...).link for argument types
# (Pointer(Void), Pointer(Void))". Channel's Sender/Receiver hit this with the
# 1.22.1 prelude.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-self-pointer-cycle.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

def raise(message) : NoReturn
  LibC.exit(98)
end

class Object
  macro property(*names, &block)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        {% if block %}
          @{{var_name}} : {{type}}? {% if name.value %} = {{name.value}} {% end %}
        {% else %}
          @{{name}}
        {% end %}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}} {% if type %} : {{type}} {% end %}
        {% if block %}
          if (%value = @{{var_name}}).nil?
            @{{var_name}} = {{yield}}
          else
            %value
          end
        {% else %}
          @{{var_name}}
        {% end %}
      end

      def {{var_name}}=(@{{var_name}}{% if type %} : {{type}} {% end %})
      end

    {% end %}
  end

end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

struct Pointer(T)
  @[Primitive(:pointer_new)]
  def self.new(address : UInt64)
  end

  def self.null : self
    new 0_u64
  end
end

struct Pointer(T)
  @[Primitive(:pointer_get)]
  def value : T
  end

  @[Primitive(:pointer_set)]
  def value=(value : T)
  end

  @[Primitive(:pointer_address)]
  def address : UInt64
  end

  def null? : Bool
    address == 0_u64
  end

  def ==(other : self) : Bool
    address == other.address
  end

  def !=(other : self) : Bool
    !(self == other)
  end
end

struct UInt64
  @[Primitive(:binary)]
  def ==(other : UInt64) : Bool
  end
end

struct Lst(T)
  @head : Pointer(T) = Pointer(T).null

  module Nd
    macro included
      property previous : ::Pointer(self) = ::Pointer(self).null
      property next : ::Pointer(self) = ::Pointer(self).null
    end
  end

  protected def self.link(p : Pointer(T), q : Pointer(T)) : Nil
    p.value.next = q
    q.value.previous = p
  end

  def head : Pointer(T)
    @head
  end

  def empty? : Bool
    @head.null?
  end

  def push(node : Pointer(T)) : Nil
    node.value.previous = node
    node.value.next = node
    @head = node
  end

  def delete(node : Pointer(T)) : Nil
    _next = node.value.next
    if node != _next
      @head = _next if @head == node
      typeof(self).link node.value.previous, _next
    else
      @head = Pointer(T).null
    end
    node.value.next = Pointer(T).null
    node.value.previous = Pointer(T).null
  end
end
CR

write_case() {
  local name="$1" body="$2"
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$body"; } > "$WORK_DIR/$name.cr"
}

write_case toplevel_includer '
struct Rx(T)
  include Lst::Nd
  property data : T

  def initialize(@data : T)
  end
end

class Ch(T)
  def run(v : T) : T
    l = Lst(Rx(T)).new
    r = Rx(T).new(v)
    l.push(pointerof(r))
    l.delete(pointerof(r))
    r.data
  end
end

LibC.exit(Ch(Int32).new.run(42))'

write_case nested_private_includer '
class Ch(T)
  private struct Rx(T)
    include Lst::Nd
    property data : T

    def initialize(@data : T)
    end
  end

  def run(v : T) : T
    l = Lst(Rx(T)).new
    r = Rx(T).new(v)
    l.push(pointerof(r))
    l.delete(pointerof(r))
    r.data
  end
end

LibC.exit(Ch(Int32).new.run(42))'

CASES=(toplevel_includer:42 nested_private_includer:42)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d self-pointer cycle case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'self-pointer cycle cases passed\n'
