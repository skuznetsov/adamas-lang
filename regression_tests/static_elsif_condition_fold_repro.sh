#!/usr/bin/env bash
# An elsif test that is statically known (a Nil local, a decided is_a?, a
# literal) must fold like the main `if` condition: the dead body or the dead
# later tests and else are not lowered. Stage2 failed in
# SymbolCollector#resolve_mixin_target, specialized as (ExprId, Nil), with
# "no overload matches intern_name for argument types (Nil)": after the
# non-foldable `if target_id` (a struct), the `elsif name_slice` body was
# lowered with name_slice : Nil. Each case exits with its expected code under
# original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/static-elsif-condition.XXXXXX")"

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

struct Eid
  def initialize(@v : Int32)
  end

  def v : Int32
    @v
  end
end

class Foo
  def k : Int32
    40
  end
end

class Counter
  def initialize
    @n = 0
  end

  def n : Int32
    @n
  end

  def bump : Nil
    @n = @n &+ 1
    nil
  end
end

def intern(s : Int32) : Int32
  s &+ 1
end

def resolve(target : Eid?, slice : Int32?) : Int32?
  if target
    target.v
  elsif slice
    intern(slice)
  else
    nil
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

add_case nil_elsif_after_struct_test 4 '
LibC.exit(resolve(Eid.new(4), nil) || 0)'

add_case live_elsif_in_other_specialization 14 '
a = resolve(Eid.new(4), nil) || 0
b = resolve(nil, 9) || 0
LibC.exit(a &+ b)'

add_case false_literal_elsif 6 '
def run(e : Eid, x : Int32?) : Int32
  if e
    e.v
  elsif false
    intern(x || 1)
  else
    0
  end
end
LibC.exit(run(Eid.new(6), nil))'

add_case decided_is_a_elsif_skips_else 40 '
def run(e : Eid?, y : Foo) : Int32
  if e
    e.v
  elsif y.is_a?(Foo)
    y.k
  else
    intern(y)
  end
end
LibC.exit(run(nil, Foo.new))'

add_case dead_middle_elsif_keeps_live_tail 3 '
def run(e : Eid?, x : Int32?, z : Int32) : Int32
  if e
    e.v
  elsif x
    intern(x)
  elsif z > 1
    z
  else
    0
  end
end
LibC.exit(run(nil, nil, 3))'

add_case nil_call_condition_keeps_side_effect 2 '
def run(e : Eid?, c : Counter) : Int32
  if e
    e.v
  elsif c.bump
    c.n &+ 100
  elsif c.bump
    c.n &+ 100
  else
    c.n
  end
end
LibC.exit(run(nil, Counter.new))'

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
  printf '%d static elsif case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all static elsif cases passed\n'
