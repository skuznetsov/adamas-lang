#!/usr/bin/env bash
# The parser turns `property x : T` (and getter/setter) into accessor nodes.
# In a module body those accessors are synthesized per includer and never
# registered under the module itself, so final HIR validation rejected a
# virtual call through the module type ("undefined method 'previous=' for
# Ctx"). The 1.22.1 prelude hits this in Thread::LinkedList(T)#push with
# T = Fiber::ExecutionContext. The module's own declarations, accessors
# included, are now source authority; an undeclared method is still
# rejected. Each positive case exits 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-accessor-source.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/generic_list_module_element.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

class Object
  macro property(*names)
    {% for name in names %}
      @{{name.var.id}} : {{name.type}}
      def {{name.var.id}} : {{name.type}}
        @{{name.var.id}}
      end
      def {{name.var.id}}=(@{{name.var.id}} : {{name.type}})
      end
    {% end %}
  end
end

module Ctx
  property previous : Ctx?
  def val : Int32
    40
  end
end

class Iso
  include Ctx
end

class Par
  include Ctx
  def val : Int32
    2
  end
end

class Mx
  def synchronize(&)
    yield
  end
end

class List(T)
  @head : T?
  @mutex = Mx.new
  def push(node : T) : Nil
    @mutex.synchronize do
      node.previous = nil
      if h = @head
        node.previous = h
      end
      @head = node
    end
  end
  def head
    @head
  end
end

l = List(Ctx).new
l.push(Par.new)
l.push(Iso.new)
r = 0
if h = l.head
  r = h.val
  if p = h.previous
    r = r + p.val
  end
end
LibC.exit(r)
CR

cat > "$WORK_DIR/nilable_module_local.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

class Object
  macro property(*names)
    {% for name in names %}
      def {{name.var.id}} : {{name.type}}
        @{{name.var.id}}
      end
      def {{name.var.id}}=(@{{name.var.id}} : {{name.type}})
      end
    {% end %}
  end
end

module Ctx
  property previous : Ctx?
  def val : Int32
    40
  end
end

class Iso
  include Ctx
end

class Par
  include Ctx
  def val : Int32
    2
  end
end

class Mx
  def synchronize(&)
    yield
  end
end

class List(T)
  @head : T?
  @mutex = Mx.new
  def push(node : T) : Nil
    @mutex.synchronize do
      node.previous = nil
      if h = @head
        node.previous = h
      end
      @head = node
    end
  end
  def head
    @head
  end
end

r = 40
y : Ctx? = Iso.new
if y
  y.previous = Par.new
  if p = y.previous
    r = r + p.val
  end
end
LibC.exit(r)
CR

cat > "$WORK_DIR/nilable_module_return.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

class Object
  macro property(*names)
    {% for name in names %}
      def {{name.var.id}} : {{name.type}}
        @{{name.var.id}}
      end
      def {{name.var.id}}=(@{{name.var.id}} : {{name.type}})
      end
    {% end %}
  end
end

module Ctx
  property previous : Ctx?
  def val : Int32
    40
  end
end

class Iso
  include Ctx
end

class Par
  include Ctx
  def val : Int32
    2
  end
end

class Mx
  def synchronize(&)
    yield
  end
end

class List(T)
  @head : T?
  @mutex = Mx.new
  def push(node : T) : Nil
    @mutex.synchronize do
      node.previous = nil
      if h = @head
        node.previous = h
      end
      @head = node
    end
  end
  def head
    @head
  end
end

def mk : Ctx?
  Iso.new
end
r = 40
if y = mk
  y.previous = Par.new
  if p = y.previous
    r = r + p.val
  end
end
LibC.exit(r)
CR

cat > "$WORK_DIR/nested_included_module.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

class Object
  macro property(*names)
    {% for name in names %}
      def {{name.var.id}} : {{name.type}}
        @{{name.var.id}}
      end
      def {{name.var.id}}=(@{{name.var.id}} : {{name.type}})
      end
    {% end %}
  end
end

module Ctx
  property previous : Ctx?
  def val : Int32
    40
  end
end

module Outer
  include Ctx
end

class Iso
  include Outer
end

class Par
  include Ctx
  def val : Int32
    2
  end
end

class Mx
  def synchronize(&)
    yield
  end
end

class List(T)
  @head : T?
  @mutex = Mx.new
  def push(node : T) : Nil
    @mutex.synchronize do
      node.previous = nil
      if h = @head
        node.previous = h
      end
      @head = node
    end
  end
  def head
    @head
  end
end

r = 40
y : Outer? = Iso.new
if y
  y.previous = Par.new
  if p = y.previous
    r = r + p.val
  end
end
LibC.exit(r)
CR

cat > "$WORK_DIR/module_declares_no_setter.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

class Object
  macro property(*names)
    {% for name in names %}
      def {{name.var.id}} : {{name.type}}
        @{{name.var.id}}
      end
      def {{name.var.id}}=(@{{name.var.id}} : {{name.type}})
      end
    {% end %}
  end
end

module Ctx
  property previous : Ctx?
  def val : Int32
    40
  end
end

class Iso
  include Ctx
end

class Par
  include Ctx
  def val : Int32
    2
  end
end

class Mx
  def synchronize(&)
    yield
  end
end

class List(T)
  @head : T?
  @mutex = Mx.new
  def push(node : T) : Nil
    @mutex.synchronize do
      node.previous = nil
      if h = @head
        node.previous = h
      end
      @head = node
    end
  end
  def head
    @head
  end
end

r = 40
y : Ctx? = Iso.new
if y
  y.nope = Par.new
  if p = y.previous
    r = r + p.val
  end
end
LibC.exit(r)
CR

CASES=(
  "generic_list_module_element:42"
  "nilable_module_local:42"
  "nilable_module_return:42"
  "nested_included_module:42"
)

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

# The module declares no `nope=`: both compilers must reject the call.
reject_name="module_declares_no_setter"
if [[ -n "$CRYSTAL_BIN" ]]; then
  if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
      "$WORK_DIR/$reject_name.cr" -o "$WORK_DIR/$reject_name.orig" > "$WORK_DIR/$reject_name.orig.log" 2>&1; then
    printf 'ORACLE FAIL: original accepts %s\n' "$reject_name" >&2
    exit 2
  fi
fi
reject_log="$WORK_DIR/$reject_name.adamas.log"
"$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$reject_name.cr" \
  -o "$WORK_DIR/$reject_name.adamas" > "$reject_log" 2>&1 || true
if grep -q "undefined method 'nope='" "$reject_log" && [[ ! -e "$WORK_DIR/$reject_name.adamas" ]]; then
  printf 'PASS %s\n' "$reject_name"
else
  printf 'FAIL %s: expected undefined method diagnostic\n' "$reject_name"
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  printf '%d module accessor source case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'module accessor source cases passed\n'
