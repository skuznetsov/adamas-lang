#!/usr/bin/env bash
# The caches keyed by a bare method name (`PG#rand`, `Rn.rand`) hold the return
# of the definition that owns that family slot: the zero-argument
# `rand : Float64`. Call lowering and expression inference let that cached
# type answer `rand(0x100000000)`, which selects `rand(max : Int) : Int`, so
# `code(...)` picked its Float64 overload. Fixing that exposed a second hole:
# `def self.rand(x)` forwards to `rand(max : Int)`, and when the force-lower
# depth limit refused the callee, the unannotated forwarder settled on Void.
# A Void-settled body is now rebuilt once after its refused callees are
# lowered at the shallower depth. Stage 2 stopped with "no overload matches
# Float64#to_s for argument types (Int32)" in File.tempname.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/family-slot-return.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  {
    cat <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Rn
  DEFAULT = PG.new

  def rand : Float64
    0.5
  end

  def rand(max : Int) : Int
    rand_int(max)
  end

  private def rand_int(max : Int32) : Int32
    max
  end

  private def rand_int(max : Int64) : Int64
    max
  end

  def rand(max : Float64) : Float64
    max
  end

  def self.rand : Float64
    DEFAULT.rand
  end

  def self.rand(x)
    DEFAULT.rand(x)
  end
end

class PG
  include Rn
end

def code(x : Int64) : Int32
  42
end

def code(x : Float64) : Int32
  1
end

def code(x : Int32) : Int32
  2
end

struct Int64
  def tag(base : Int32) : Int32
    42
  end
end

def run(&)
  yield
end

class Box
  @v = 0

  def put(x : Int32) : Nil
    @v = x
  end

  def v : Int32
    @v
  end
end

def bld(&)
  b = Box.new
  yield b
  b.v
end
HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

# name:expected-exit
CASES=()

add_case() {
  CASES+=("$1:$2")
  write_case "$1" "$3"
}

add_case instance_int_overload 42 '
LibC.exit(run { code(PG.new.rand(0x100000000)) })'

add_case module_forwarder_literal 42 '
LibC.exit(run { code(Rn.rand(0x100000000)) })'

add_case module_forwarder_local 42 '
x = 0x100000000
LibC.exit(run { code(Rn.rand(x)) })'

# Unannotated class method: `Rn.rand(x)` is refused by the depth limit while
# `Foo.t` is lowered.
add_case depth_refused_forwarder 42 '
class Foo
  def self.t
    run { code(Rn.rand(0x100000000)) }
  end
end
LibC.exit(Foo.t)'

add_case depth_refused_receiver_call 42 '
class Foo
  def self.t
    bld { |io| io.put(Rn.rand(0x100000000).tag(36)) }
  end
end
LibC.exit(Foo.t)'

# The slot owner still answers its own calls.
add_case zero_arg_slot_owner 1 '
LibC.exit(run { code(Rn.rand) })'

add_case float_overload 1 '
LibC.exit(run { code(Rn.rand(2.5)) })'

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}" want="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$want" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$want" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}" want="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s: compile failed\n' "$name" >&2
    tail -5 "$log" >&2
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  got="$(exit_code_of "$run_log")"
  if [[ "$got" == "$want" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: exit %s, expected %s\n' "$name" "$got" "$want" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d family-slot return case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all family-slot return cases passed\n'
