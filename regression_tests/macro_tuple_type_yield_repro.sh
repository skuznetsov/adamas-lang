#!/usr/bin/env bash
# A `{% for type, i in U %}` loop over a forall-bound Tuple type `U` must
# iterate the tuple's element types, and a block's yield type must be
# inferred through a `{% begin %}` macro body. V2 iterated nothing for a
# Tuple TypeNode, so `count_u` summed only `main`, and yield inference saw
# the unexpanded `{% begin %}` node: forwarding the yielded tuple through
# `*others : Int32 | Char` and `break` lost its type ("no overload matches").
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-tuple-type-yield.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

CASES=()

# add_case name expected-stderr-lines(|-separated) body
add_case() {
  CASES+=("$1")
  printf '%s\n' "$2" | tr '|' '\n' > "$WORK_DIR/$1.want"
  printf '%s\nexit 0\n' "$3" > "$WORK_DIR/$1.cr"
}

add_case macro_for_over_tuple_type '31|301' '
def count_u(main, others : U) forall U
  n = main
  {% for type, type_index in U %}
    n += others[{{type_index}}]
  {% end %}
  n
end

def count_y(main, others : U, &) forall U
  {% begin %}
    yield({main, {% for type, type_index in U %} others[{{type_index}}], {% end %}})
  {% end %}
end

a = count_u(1, {10, 20})
b = 0
count_y(1, {100, 200}) { |t| b = t[0] + t[1] + t[2] }
STDERR.puts a
STDERR.puts b'

add_case break_through_macro_begin_yield 'Tuple(Int64, Int32, Char)|1|5|a' '
def count_y(main, others : U, &) forall U
  {% begin %}
    yield({main, {% for type, type_index in U %} others[{{type_index}}], {% end %}})
  {% end %}
end

def wrap(*others : Int32 | Char, &)
  count_y(1_i64, others) { |e| yield e }
end

def first_e(*others : Int32 | Char)
  x = wrap(*others) { |e| break e }
  x
end

r = first_e(5, '\''a'\'')
STDERR.puts typeof(r)
STDERR.puts r[0]
STDERR.puts r[1]
STDERR.puts r[2]'

stderr_of() {
  awk '/^=== STDERR ===$/ { on = 1; next } /^\[EXIT: / { on = 0 } on' "$1"
}

check_output() {
  local label="$1" name="$2" run_log="$3"
  if stderr_of "$run_log" | diff -u "$WORK_DIR/$name.want" - > "$WORK_DIR/$name.$label.diff"; then
    return 0
  fi
  return 1
}

# Original Crystal first, so the expected outputs themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${CASES[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if ! check_output orig "$name" "$WORK_DIR/$name.orig.run"; then
      printf 'ORACLE FAIL: original output differs for %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.diff" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${CASES[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 600 8192 "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ ! -x "$WORK_DIR/$name.adamas" ]]; then
    printf 'FAIL %s: compile failed\n' "$name" >&2
    grep -v '^\[RUN_SAFE' "$log" | grep -m3 -i 'error\|overload' >&2 || tail -5 "$log" >&2
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if check_output adamas "$name" "$run_log"; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: output differs\n' "$name" >&2
    cat "$WORK_DIR/$name.adamas.diff" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d macro tuple type yield case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all macro tuple type yield cases passed\n'
