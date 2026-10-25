#!/usr/bin/env bash
# `Fiber.new(name, ec, &block)` is served only by an explicit
# `def self.new(name : String? = nil, ec : EC = ..., &proc)`; no initialize
# accepts that shape. The eager initializer pre-lowering in lower_call then
# fell back to the bare `Fiber#initialize` registration alias (the last
# declared `initialize(stack : Int32, thread)`), bound the call types to it
# and lowered `thread.handler = stack` with thread : EC::Par, failing with
# "undefined method 'handler=' for EC::Par" - the 1.22.1 prelude's
# `gc_thread_handler=` from ExecutionContext#spawn. Each case exits 42 under
# original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/explicit-new-unselected-init.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/module_spawn.cr" <<'CR'
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

class Thread
  @handler = 0

  def handler=(@handler : Int32)
  end
end

class Fiber
  def self.new(name : String? = nil, ec : EC = EC.current, &proc : ->) : self
    new(name, 7, ec, &proc)
  end

  def initialize(@name : String?, @stack : Int32, @ec : EC = EC.current, &@proc : ->)
  end

  def initialize(stack : Int32, thread)
    @name = nil
    @stack = stack
    @ec = EC.current
    @proc = ->{}
    thread.handler = stack
  end

  def stack : Int32
    @stack
  end
end

module EC
  def self.current : EC
    Par.new
  end

  def spawn(*, name : String? = nil, &block : ->) : Fiber
    Fiber.new(name, self, &block)
  end

  class Par
    include EC
  end
end

f = EC::Par.new.spawn(name: "x") { }
LibC.exit(f.stack + 35)
CR

cat > "$WORK_DIR/toplevel_new.cr" <<'CR'
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

class Thread
  @handler = 0

  def handler=(@handler : Int32)
  end
end

class Fiber
  def self.new(name : String? = nil, ec : EC = EC.current, &proc : ->) : self
    new(name, 7, ec, &proc)
  end

  def initialize(@name : String?, @stack : Int32, @ec : EC = EC.current, &@proc : ->)
  end

  def initialize(stack : Int32, thread)
    @name = nil
    @stack = stack
    @ec = EC.current
    @proc = ->{}
    thread.handler = stack
  end

  def stack : Int32
    @stack
  end
end

module EC
  def self.current : EC
    Par.new
  end

  def spawn(*, name : String? = nil, &block : ->) : Fiber
    Fiber.new(name, self, &block)
  end

  class Par
    include EC
  end
end

f = Fiber.new("x", EC::Par.new) { }
LibC.exit(f.stack + 35)
CR

cat > "$WORK_DIR/class_spawn.cr" <<'CR'
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

class Thread
  @handler = 0

  def handler=(@handler : Int32)
  end
end

class Fiber
  def self.new(name : String? = nil, ec : EC = EC.current, &proc : ->) : self
    new(name, 7, ec, &proc)
  end

  def initialize(@name : String?, @stack : Int32, @ec : EC = EC.current, &@proc : ->)
  end

  def initialize(stack : Int32, thread)
    @name = nil
    @stack = stack
    @ec = EC.current
    @proc = ->{}
    thread.handler = stack
  end

  def stack : Int32
    @stack
  end
end

module EC
  def self.current : EC
    Par.new
  end


  class Par
    include EC

    def spawn(*, name : String? = nil, &block : ->) : Fiber
        Fiber.new(name, self, &block)
    end
  end
end

f = EC::Par.new.spawn(name: "x") { }
LibC.exit(f.stack + 35)
CR

CASES=(
  "module_spawn:42"
  "toplevel_new:42"
  "class_spawn:42"
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
  printf '%d explicit new unselected initializer case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'explicit new unselected initializer cases passed\n'
