#!/usr/bin/env bash
# `x.is_a?(A) || x.is_a?(B)` narrows `x` to `A | B` when truthy (original
# Crystal's TypeFilters.or). V2's is_a? target collector handled `&&` only,
# so `||` narrowed nothing and `next unless node.is_a?(A) || node.is_a?(B)`
# left `node : Node?` -> "no overload matches kind for (Nil | Node)". The
# stage-2 shape is compute_yield_types_with_macro_bodies (MacroFor/MacroIf).
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/is-a-or-narrowing.XXXXXX")"

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

abstract class Node
end

class A < Node
end

class B < Node
end

class C < Node
end

def kind(x : A) : Int32
  1
end

def kind(x : B) : Int32
  2
end

def kind(x : Int32) : Int32
  x
end

def kind(x : Bool) : Int32
  x ? 5 : 6
end

def node_at(i : Int32) : Node?
  if i == 0
    A.new
  elsif i == 1
    B.new
  elsif i == 2
    C.new
  else
    nil
  end
end

def value_at(i : Int32) : Int32 | Bool | Nil
  i == 0 ? 3 : (i == 1 ? true : nil)
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

add_case return_unless_guard 21 '
def run(i : Int32) : Int32
  node = node_at(i)
  return 0 unless node.is_a?(A) || node.is_a?(B)
  kind(node)
end
LibC.exit(run(0) &+ run(1) &* 10 &+ run(2) &+ run(3))'

add_case next_unless_guard_in_loop 12 '
r = 0
i = 0
while i < 4
  node = node_at(i)
  i &+= 1
  next unless node.is_a?(A) || node.is_a?(B)
  r = r &* 10 &+ kind(node)
end
LibC.exit(r)'

add_case guard_then_if_else_split 52 '
r = 0
i = 0
while i < 4
  node = node_at(i)
  i &+= 1
  next unless node.is_a?(A) || node.is_a?(B)
  v = if node.is_a?(A)
        kind(node) &+ 4
      else
        kind(node)
      end
  r = r &* 10 &+ v
end
LibC.exit(r)'

add_case value_union_if_condition 44 '
def run(i : Int32) : Int32
  v = value_at(i)
  if v.is_a?(Int32) || v.is_a?(Bool)
    kind(v)
  else
    9
  end
end
LibC.exit(run(0) &* 10 &+ run(1) &+ run(2))'

add_case one_sided_or_does_not_narrow 2 '
def run(i : Int32, flag : Bool) : Int32
  v = value_at(i)
  if v.is_a?(Int32) || flag
    1
  else
    v.nil? ? 2 : 3
  end
end
LibC.exit(run(2, false))'

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
  printf '%d is_a? || narrowing case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all is_a? || narrowing cases passed\n'
