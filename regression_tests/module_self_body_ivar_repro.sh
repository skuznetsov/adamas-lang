#!/usr/bin/env bash
# A def in a module whose includers are all classes was also lowered with
# self = the module. That body has no ivars, so `@syscall` fell back to a
# method named `syscall`; with the block method `syscall(& : -> U)` the ivar
# became U and `.get` failed ("undefined method 'get' for U"; in the 1.22.1
# prelude, Fiber::ExecutionContext::Scheduler#detach_syscall? resolved `.get`
# on Crystal::LRUCache). Calls on such a module value dispatch by type id to
# the includers' copies, so the module-self body is no longer lowered. The
# enum only makes the lowering path reachable. Each case exits 42 under
# original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-self-body-ivar.XXXXXX")"

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

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end
CR

cat > "$WORK_DIR/typed_body.cr" <<'CR'
enum Dummy
  A
end

struct Cell
  def initialize(@v : Int32)
  end

  def get(order : Symbol) : Int32
    @v
  end
end

module Ctx
  module Sch
    @syscall = Cell.new(40)

    def syscall(& : -> U) : U forall U
      yield
    end

    protected def leave?(value : Int32) : Int32
      value
    end

    protected def detach? : Int32
      value = @syscall.get(:relaxed)
      leave?(value)
    end
  end
end

class Par
  include Ctx
  class Sch
    include Ctx::Sch
    def initialize
    end
  end
  def initialize
    @s = Sch.new
  end
  def each_sched(& : Ctx::Sch ->) : Nil
    yield @s
  end
end

class Iso
  include Ctx
  include Ctx::Sch
  def initialize
  end
  def each_sched(& : Ctx::Sch ->) : Nil
    yield self
  end
end

module Ctx
  def self.mk(i : Int32) : Ctx?
    i == 0 ? Par.new : Iso.new
  end

  def self.run : Int32
    Monitor.new.scan
  end

  class Monitor
    def initialize
      @a = Ctx.mk(0)
      @b = Ctx.mk(1)
    end

    def scan : Int32
      r = 0
      if c = @a
        c.each_sched { |s| r = r + s.detach? }
      end
      if c = @b
        c.each_sched { |s| r = r + s.detach? }
      end
      r - 38
    end
  end
end

LibC.exit(Ctx.run)
CR

# Unannotated defs, with unrelated `get` overloads the bad fallback could pick.
cat > "$WORK_DIR/untyped_body.cr" <<'CR'
enum Dummy
  A
end

class Lru
  def get(order : Symbol) : Lru
    self
  end
end

struct Cell
  def initialize(@v : Int32)
  end

  def get(order : Symbol) : Int32
    @v
  end
end

class Other
  def get(x : String) : Int32
    7
  end
end

module Ctx
  module Sch
    @syscall = Cell.new(40)

    def syscall(& : -> U) : U forall U
      yield
    end

    protected def leave?(value : Int32)
      value
    end

    protected def detach?
      value = @syscall.get(:relaxed)
      leave?(value)
    end
  end
end

class Par
  include Ctx
  class Sch
    include Ctx::Sch
    def initialize
    end
  end
  def initialize
    @s = Sch.new
  end
  def each_sched(& : Ctx::Sch ->) : Nil
    yield @s
  end
end

class Iso
  include Ctx
  include Ctx::Sch
  def initialize
  end
  def each_sched(& : Ctx::Sch ->) : Nil
    yield self
  end
end

module Ctx
  def self.mk(i : Int32) : Ctx?
    i == 0 ? Par.new : Iso.new
  end

  def self.run : Int32
    Monitor.new.scan
  end

  class Monitor
    def initialize
      @a = Ctx.mk(0)
      @b = Ctx.mk(1)
    end

    def scan : Int32
      r = 0
      if c = @a
        c.each_sched { |s| r = r + s.detach? }
      end
      if c = @b
        c.each_sched { |s| r = r + s.detach? }
      end
      r - 38
    end
  end
end

LibC.exit(Ctx.run)
CR

# super from an includer's override still reaches the module def.
cat > "$WORK_DIR/super_into_module.cr" <<'CR'
enum Dummy
  A
end

module M
  def val
    @x + 1
  end
end

class A
  include M
  def initialize(@x : Int32)
  end

  def val
    super + 10
  end
end

class B
  include M
  def initialize(@x : Int32)
  end
end

def pick(i : Int32) : M
  i == 0 ? A.new(20) : B.new(10)
end

LibC.exit(pick(0).val + pick(1).val)
CR

CASES=(
  "typed_body:42"
  "untyped_body:42"
  "super_into_module:42"
)

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  cat "$WORK_DIR/header.cr" "$WORK_DIR/$name.cr" > "$WORK_DIR/$name.full.cr"
  mv "$WORK_DIR/$name.full.cr" "$WORK_DIR/$name.cr"
done

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
  printf '%d module-self body case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'module-self body cases passed\n'
