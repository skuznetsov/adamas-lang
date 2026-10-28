#!/usr/bin/env bash
# `Enumerable#zip(*others, &)` forwards to `Enumerable.zip(main, others : U, &)`,
# whose `{% begin %}` body yields `{elem, other_elem0, ...}` built by a
# `{% for type, i in U %}` loop. V2 could not infer that yield type: the
# single-segment receiver `Enumerable` resolved to the instance method,
# `*others` was typed as its restriction instead of the argument tuple,
# the `{% begin %}` body was never expanded for yield inference, the
# `offset = 0` default of `each_with_index` left the index untyped, and
# locals defined only by the expansion were unresolvable. Zipping arrays
# of tuples then produced `Int32` elements ("block destructuring requires
# Tuple or Array") or dropped the call. `NamedTupleType#==` in the
# compiler itself (`@entries.zip(other.entries).all? do |(k1, t1), (k2, t2)|`)
# is the stage-2 shape. Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zip-nested-tuple.XXXXXX")"

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

add_case block_element_type 'Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))' '
a = [{1, 2}]
b = [{30, 40}]
a.zip(b) { |e| STDERR.puts typeof(e) }'

add_case zip_result_type 'Array(Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32)))|Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))' '
x = [{1, 2}].zip([{30, 40}])
STDERR.puts typeof(x)
x.each { |e| STDERR.puts typeof(e) }'

add_case zip_result_values '2|4|b|6|9|8' '
x = [1, 2].zip([3, 4])
STDERR.puts x[1][0]
STDERR.puts x[1][1]
y = ["a", "b"].zip([{1, 2}, {5, 6}])
STDERR.puts y[1][0]
STDERR.puts y[1][1][1]
z = [{7, 8}].zip([9])
STDERR.puts z[0][1]
STDERR.puts z[0][0][1]'

add_case destructuring_each '73' '
s = 0
[{1, 2}].zip([{30, 40}]).each do |(a, b), (c, d)|
  s = a + b + c + d
end
STDERR.puts s'

add_case destructuring_all 'true' '
r = [{1, 2}].zip([{30, 40}]).all? do |(a, b), (c, d)|
  a + b + c + d == 73
end
STDERR.puts r'

add_case named_tuple_type_equality 'false|true' '
abstract class Ty
end

class A < Ty
end

class B < Ty
end

class NT < Ty
  getter entries : Array({String, Ty})

  def initialize(@entries : Array({String, Ty}))
  end

  def ==(other : Ty) : Bool
    return false unless other.is_a?(NT)
    return false unless @entries.size == other.entries.size
    @entries.zip(other.entries).all? do |(k1, t1), (k2, t2)|
      k1 == k2 && t1 == t2
    end
  end
end

a = A.new
x = NT.new([{"a", a.as(Ty)}, {"b", B.new.as(Ty)}])
y = NT.new([{"a", a.as(Ty)}, {"b", B.new.as(Ty)}])
STDERR.puts(x == y)
STDERR.puts(x == x)'

add_case class_method_zip_receiver 'Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))' '
a = [{1, 2}]
b = [{30, 40}]
Enumerable.zip(a, {b}) { |e| STDERR.puts typeof(e) }'

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
  printf '%d zip nested tuple case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all zip nested tuple cases passed\n'
