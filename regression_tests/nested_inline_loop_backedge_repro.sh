#!/usr/bin/env bash
# Inline-yield loops save the last body value of a caller local
# (@inline_loop_var_backedge_values) so the loop's header phi gets the right
# back edge. The saved values were keyed by name only, so the value an inner
# `rep` loop saved outlived that loop: returning from the inner `rep` put it
# back into the caller frame and the outer loop used it as its own back edge.
# That value lives in the inner loop body and does not reach the outer back
# edge, so `rep(2) { rep(2) { |q| off = off &+ q &+ 1 } }` returned 0 instead
# of 6. Saved values now carry the depth of the loop they belong to and are
# ignored once that loop is lowered.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested-loop-backedge.XXXXXX")"

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

def rep(n : Int32, &)
  i = 0
  while i < n
    yield i
    i &+= 1
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

# The outer loop takes its back edge from the inner loop.
add_case two_levels 6 '
def run : Int32
  off = 0
  rep(2) do |k|
    rep(2) do |q|
      off = off &+ q &+ 1
    end
  end
  off
end
LibC.exit(run)'

add_case three_levels 24 '
def run : Int32
  off = 0
  rep(2) do |a|
    rep(2) do |b|
      rep(3) do |c|
        off = off &+ c &+ 1
      end
    end
  end
  off
end
LibC.exit(run)'

add_case method_owner 15 '
class L
  def rep2(n : Int32, &)
    i = 0
    while i < n
      yield i
      i &+= 1
    end
  end

  def run : Int32
    off = 0
    rep2(3) do |k|
      rep2(2) do |q|
        off = off &+ q &+ 2
      end
    end
    off
  end
end
LibC.exit(L.new.run)'

# A sibling loop after the writing loop reads the caller local.
add_case sibling_inner 124 '
def run : Int32
  off = 0
  x = 0
  rep(2) do |k|
    rep(2) do |q|
      off = off &+ 1
    end
    rep(2) do |q|
      x = x &+ off
    end
  end
  x &* 10 &+ off
end
LibC.exit(run)'

# A `break` in the outer block reads the value after the inner loop.
add_case break_after_inner 6 '
def run : Int32
  off = 0
  rep(5) do |k|
    rep(2) do |q|
      off = off &+ 1
    end
    break if off > 5
  end
  off
end
LibC.exit(run)'

# The outer block writes the local again after the inner loop.
add_case write_after_inner 33 '
def run : Int32
  off = 1
  rep(2) do |k|
    rep(2) do |q|
      off = off &+ 1
    end
    off = off &* 3
  end
  off
end
LibC.exit(run)'

# A plain `while` inside the block, not an inlined callee loop.
add_case plain_while_inner 12 '
def run : Int32
  off = 0
  rep(3) do |k|
    j = 0
    while j < 2
      off = off &+ k &+ 1
      j &+= 1
    end
  end
  off
end
LibC.exit(run)'

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
  printf '%d nested loop back-edge case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all nested loop back-edge cases passed\n'
