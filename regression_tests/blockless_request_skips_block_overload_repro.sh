#!/usr/bin/env bash
# A blockless request for a family name (`args.each_with_index` without a
# block) was bound to a block-taking overload when an earlier block call had
# already specialized only `Enumerable#each_with_index(offset, &)` onto the
# receiver. The untyped-prefix fallback in lower_function_if_needed then
# materialized that Nil-returning body under the blockless name, so the chained
# `any?` resolved on Pointer ("no overload matches Array#[]? (Pointer)")
# instead of the `Iterable#each_with_index(offset)` iterator.
# The compiler itself has the shape in AstToHir#repair_named_tuple_call_arguments.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/blockless-block-overload.XXXXXX")"

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

add_case block_call_before_iterator '5 0|6 1|true' '
class M
  def first(args : Array(UInt32)) : Nil
    args.each_with_index do |a, i|
      STDERR.puts "#{a} #{i}"
    end
  end

  def run(args : Array(UInt32), ps : Array(String)) : Nil
    affected = args.each_with_index.any? do |argument, index|
      p = ps[index + 1]?
      p && argument > 5
    end
    STDERR.puts affected
  end
end
m = M.new
m.first([5_u32, 6_u32])
m.run([5_u32, 6_u32], ["a", "b", "c"])'

add_case iterator_before_block_call 'false|7 0|8 1' '
class M
  def run(args : Array(UInt32), ps : Array(String)) : Nil
    affected = args.each_with_index.any? do |argument, index|
      p = ps[index]?
      p && argument > 8
    end
    STDERR.puts affected
  end

  def last(args : Array(UInt32)) : Nil
    args.each_with_index do |a, i|
      STDERR.puts "#{a} #{i}"
    end
  end
end
m = M.new
m.run([7_u32, 8_u32], ["a", "b", "c"])
m.last([7_u32, 8_u32])'

add_case toplevel_block_then_iterator '1 0|2 1|2' '
xs = [1_u32, 2_u32]
xs.each_with_index { |a, i| STDERR.puts "#{a} #{i}" }
STDERR.puts xs.each_with_index.count { |a, i| i >= 0 }'

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
  printf '%d blockless block-overload case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all blockless block-overload cases passed\n'
