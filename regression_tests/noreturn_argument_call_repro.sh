#!/usr/bin/env bash
# A call whose argument is NoReturn never runs: original Crystal types it
# NoReturn without overload lookup. Stage2 failed in Parser#new_call_node,
# specialized with `block : Nil`, with "no overload matches CallNode.new ...
# expects Nil, not NoReturn" for `CallNode.new(..., block.not_nil!, ...)`.
# Three defects combined: `x.not_nil!` on a Nil receiver was folded to `x`
# instead of calling Nil#not_nil!; a no-parens call to a NoReturn method did
# not end its block, so the enclosing call still resolved its overload; and
# the inferred-type pre-checks for `.new` and class-method calls rejected a
# NoReturn argument before arguments were lowered. A `Proc(..., NoReturn)`
# call, with or without parentheses, did not end its block either. Each
# case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/noreturn-argument-call.XXXXXX")"

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

struct Nil
  def not_nil! : NoReturn
    LibC.exit(99)
  end
end

struct Eid
  def initialize(@index : Int32)
  end

  def index : Int32
    @index
  end

  def not_nil! : Eid
    self
  end
end

class Cn
  @b : Int32

  def initialize(n : Int32, block : Nil, named : Int32)
    @b = 1
  end

  def initialize(n : Int32, block : Eid, named : Int32)
    @b = block.index
  end

  def initialize(n : Int32, block : Nil)
    @b = 3
  end

  def initialize(n : Int32, block : Eid)
    @b = 4
  end

  def b : Int32
    @b
  end
end

module Cm
  def self.pick(x : Nil) : Int32
    2
  end
end

def take_nil(x : Nil) : Int32
  1
end

def take_two(x : Nil, y : Int32) : Int32
  y
end

def mk(n : Int32, block : Eid?, named : Int32? = nil) : Cn
  has_block = !block.nil?
  if actual = named
    if has_block
      Cn.new(n, block.not_nil!, actual)
    else
      Cn.new(n, nil, actual)
    end
  elsif has_block
    Cn.new(n, block.not_nil!)
  else
    Cn.new(n, nil)
  end
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

add_case dead_new_arm_with_named 1 '
LibC.exit(mk(1, nil, 3).b)'

add_case dead_new_arm_positional 3 '
LibC.exit(mk(1, nil).b)'

add_case live_new_arm 7 '
LibC.exit(mk(1, Eid.new(7), 3).b)'

add_case new_with_nil_not_nil 99 '
def run(blk : Nil) : Int32
  Cn.new(1, blk.not_nil!).b
end
LibC.exit(run(nil))'

add_case parenthesized_call_on_bottom_receiver 99 '
def run(blk : Nil) : Int32
  Cn.new(1, blk.not_nil!).b()
end
LibC.exit(run(nil))'

add_case top_level_call_with_nil_not_nil 99 '
def run(blk : Eid?) : Int32
  if blk
    return 5
  end
  take_nil(blk.not_nil!)
end
LibC.exit(run(nil))'

add_case class_method_with_nil_not_nil 99 '
def run(blk : Nil) : Int32
  Cm.pick(blk.not_nil!)
end
LibC.exit(run(nil))'

add_case later_argument_not_evaluated 99 '
def run(blk : Nil) : Int32
  take_two(blk.not_nil!, LibC.exit(7))
end
LibC.exit(run(nil))'

add_case non_nil_not_nil_is_self 6 '
LibC.exit(Eid.new(6).not_nil!.index)'

# Proc#call is lowered on its own path; a NoReturn proc ends the block too.
add_case proc_call_noreturn_argument_skipped 8 '
def take_int(v : Int32) : Int32
  v
end
def run(flag : Bool, cb : Proc(NoReturn)) : Int32
  if flag
    take_int(cb.call)
  else
    8
  end
end
LibC.exit(run(false, -> { LibC.exit(77) }))'

add_case proc_call_noreturn_argument_runs 77 '
def take_int(v : Int32) : Int32
  v
end
def run(flag : Bool, cb : Proc(NoReturn)) : Int32
  if flag
    take_int(cb.call)
  else
    8
  end
end
LibC.exit(run(true, -> { LibC.exit(77) }))'

add_case proc_call_with_args_noreturn_argument_runs 77 '
def take_int(v : Int32) : Int32
  v
end
def run(flag : Bool, cb : Proc(Int32, NoReturn)) : Int32
  if flag
    take_int(cb.call(77))
  else
    8
  end
end
LibC.exit(run(true, ->(c : Int32) { LibC.exit(c) }))'

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
      printf 'ORACLE FAIL: original %s exited %s, not %s\n' "$name" \
        "$(exit_code_of "$WORK_DIR/$name.orig.run")" "$want" >&2
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
    grep -v '^\[RUN_SAFE' "$log" | grep -m3 -i 'error\|overload' >&2 || tail -5 "$log" >&2
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
  printf '%d NoReturn argument call case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all NoReturn argument call cases passed\n'
