#!/usr/bin/env bash
# A virtual call through a module type reaches every type that includes the
# module. Final HIR validation only counted class subclasses as descendants,
# so a method declared by the includers alone was rejected: the 1.22.1
# prelude's ExecutionContext::Monitor failed with "undefined method
# 'each_scheduler' for Fiber::ExecutionContext" (defined only by Parallel and
# Isolated). Includers, modules including the module, and subclasses of
# includers now count; a method no includer declares is still rejected.
# Each positive case exits 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-includer-method.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/direct_includers.cr" <<'CR'
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

module Ctx
end

class Par
  include Ctx
  def each_sched(&)
    yield 40
  end
end

class Iso
  include Ctx
  def each_sched(&)
    yield 2
  end
end

def mk(i : Int32) : Ctx?
  i == 0 ? Par.new : Iso.new
end

r = 0
if c = mk(0)
  c.each_sched { |v| r = r + v }
end
if c = mk(1)
  c.each_sched { |v| r = r + v }
end
LibC.exit(r)
CR

cat > "$WORK_DIR/nested_module_and_subclass.cr" <<'CR'
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

module Ctx
end

class Par
  include Ctx
  def each_sched(&)
    yield 40
  end
end

module Mid
  include Ctx
end

class IsoBase
  include Mid
end

class Iso < IsoBase
  def each_sched(&)
    yield 2
  end
end

def mk(i : Int32) : Ctx?
  i == 0 ? Par.new : Iso.new
end

r = 0
if c = mk(0)
  c.each_sched { |v| r = r + v }
end
if c = mk(1)
  c.each_sched { |v| r = r + v }
end
LibC.exit(r)
CR

cat > "$WORK_DIR/no_includer_declares.cr" <<'CR'
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

module Ctx
end

class Par
  include Ctx
  def each_sched(&)
    yield 40
  end
end

class Iso
  include Ctx
  def each_sched(&)
    yield 2
  end
end

def mk(i : Int32) : Ctx?
  i == 0 ? Par.new : Iso.new
end

r = 0
if c = mk(0)
  c.nope { |v| r = r + v }
end
if c = mk(1)
  c.nope { |v| r = r + v }
end
LibC.exit(r)
CR

CASES=(
  "direct_includers:42"
  "nested_module_and_subclass:42"
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

# No includer declares `nope`: both compilers must reject the call.
reject_name="no_includer_declares"
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
if grep -q "undefined method 'nope'" "$reject_log" && [[ ! -e "$WORK_DIR/$reject_name.adamas" ]]; then
  printf 'PASS %s\n' "$reject_name"
else
  printf 'FAIL %s: expected undefined method diagnostic\n' "$reject_name"
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  printf '%d module includer method case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'module includer method cases passed\n'
