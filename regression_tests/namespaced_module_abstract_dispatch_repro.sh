#!/usr/bin/env bash
# Instance methods of a namespaced module (`module Fib::EC`, or `module EC`
# nested in `class Fib`) were never registered on the module: the nested
# module pass kept only class methods. A call on a value of the module type
# then had no source family and failed with "undefined method 'pool?' for
# Fib::EC" - the 1.22.1 prelude's `ExecutionContext.each(&.stack_pool?)`
# against `abstract def stack_pool?` in `module Fiber::ExecutionContext`.
# A top-level module with the same body already worked. Each case exits 42
# under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/namespaced-module-abstract.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/path_module_try.cr" <<'CR'
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
end

class Object
  def try(&)
    yield self
  end
end

struct Nil
  def try(&)
    self
  end
end

class Pool
  def size : Int32
    40
  end
end

class L(T)
  @head : T?

  def push(node : T) : Nil
    @head = node
  end

  def each(&) : Nil
    if node = @head
      yield node
    end
  end
end

class Fib
end

module Fib::EC
  @@all = L(EC).new

  def self.add(e : EC) : Nil
    @@all.push(e)
  end

  def self.each(&) : Nil
    @@all.each { |e| yield e }
  end

  abstract def pool? : Pool?
end

module Fib::EC
  class Par
    include EC

    def pool? : Pool?
      Pool.new
    end
  end

  class Iso
    include EC

    def pool? : Pool?
      nil
    end
  end
end

Fib::EC.add(Fib::EC::Iso.new)
Fib::EC.add(Fib::EC::Par.new)
r = 0
Fib::EC.each { |e| r = e.pool?.try(&.size) || 0 }
LibC.exit(r + 2)
CR

cat > "$WORK_DIR/path_module_block_shorthand.cr" <<'CR'
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
end

class Object
  def try(&)
    yield self
  end
end

struct Nil
  def try(&)
    self
  end
end

class Pool
  def size : Int32
    40
  end
end

class L(T)
  @head : T?

  def push(node : T) : Nil
    @head = node
  end

  def each(&) : Nil
    if node = @head
      yield node
    end
  end
end

class Fib
end

module Fib::EC
  @@all = L(EC).new

  def self.add(e : EC) : Nil
    @@all.push(e)
  end

  def self.each(&) : Nil
    @@all.each { |e| yield e }
  end

  abstract def pool? : Pool?
end

module Fib::EC
  class Par
    include EC

    def pool? : Pool?
      Pool.new
    end
  end

  class Iso
    include EC

    def pool? : Pool?
      nil
    end
  end
end

Fib::EC.add(Fib::EC::Iso.new)
Fib::EC.add(Fib::EC::Par.new)
r = 0
Fib::EC.each(&.pool?.try { |p| r = p.size })
LibC.exit(r + 2)
CR

cat > "$WORK_DIR/class_nested_module.cr" <<'CR'
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
end

class Object
  def try(&)
    yield self
  end
end

struct Nil
  def try(&)
    self
  end
end

class Pool
  def size : Int32
    40
  end
end

class L(T)
  @head : T?

  def push(node : T) : Nil
    @head = node
  end

  def each(&) : Nil
    if node = @head
      yield node
    end
  end
end

class Fib
module EC
  @@all = L(EC).new

  def self.add(e : EC) : Nil
    @@all.push(e)
  end

  def self.each(&) : Nil
    @@all.each { |e| yield e }
  end

  abstract def pool? : Pool?
end
end

class Fib
module EC
  class Par
    include EC

    def pool? : Pool?
      Pool.new
    end
  end

  class Iso
    include EC

    def pool? : Pool?
      nil
    end
  end
end
end

Fib::EC.add(Fib::EC::Iso.new)
Fib::EC.add(Fib::EC::Par.new)
r = 0
Fib::EC.each { |e| if p = e.pool?; r = p.size; end }
LibC.exit(r + 2)
CR

CASES=(
  "path_module_try:42"
  "path_module_block_shorthand:42"
  "class_nested_module:42"
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

if [[ "$failures" -ne 0 ]]; then
  printf '%d namespaced module abstract dispatch case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'namespaced module abstract dispatch cases passed\n'
