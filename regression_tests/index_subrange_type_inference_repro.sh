#!/usr/bin/env bash
# Expression type inference read every `x[...]` on a collection as an element
# read. `body[0...index]` on Array(ExprId) was inferred as ExprId, so in
# AstToHir#class_registration_body `flattened ||= body[0...index]` widened
# the local to `ExprId | Array(ExprId)` and stage2 failed with "no overload
# matches append_class_registration_expr". `[](range)` (literal or variable)
# and `[](start, count)` now infer the sub-collection type. Each case exits
# with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/index-subrange-type.XXXXXX")"

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

struct Range(B, E)
  def initialize(@begin : B, @end : E, @exclusive : Bool = false)
  end

  def end : E
    @end
  end
end

class Array(T)
  def initialize(@n : Int32)
  end

  def [](index : Int32) : T
    @n
  end

  def [](range : Range) : Array(T)
    Array(T).new(range.end)
  end

  def [](start : Int32, count : Int32) : Array(T)
    Array(T).new(count)
  end
end

class Hash(K, V)
  def initialize(@v : V)
  end

  def [](key : K) : V
    @v
  end
end

def code(x : Array(Int32).class) : Int32
  7
end

def code(x : Int32.class) : Int32
  3
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

add_case literal_range 7 '
def pick(a : Array(Int32), idx : Int32) : Int32
  code(typeof(a[0...idx]))
end

LibC.exit(pick(Array(Int32).new(1), 2))'

add_case range_variable 7 '
def pick(a : Array(Int32), idx : Int32) : Int32
  r = 0..idx
  code(typeof(a[r]))
end

LibC.exit(pick(Array(Int32).new(1), 2))'

add_case start_count 7 '
def pick(a : Array(Int32), idx : Int32) : Int32
  code(typeof(a[0, idx]))
end

LibC.exit(pick(Array(Int32).new(1), 2))'

add_case element_index_control 3 '
def pick(a : Array(Int32), idx : Int32) : Int32
  code(typeof(a[idx]))
end

LibC.exit(pick(Array(Int32).new(1), 2))'

add_case hash_range_key_control 3 '
def pick(h : Hash(Range(Int32, Int32), Int32), idx : Int32) : Int32
  code(typeof(h[0...idx]))
end

LibC.exit(pick(Hash(Range(Int32, Int32), Int32).new(4), 2))'

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
  printf '%d index subrange type inference case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all index subrange type inference cases passed\n'
