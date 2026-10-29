#!/usr/bin/env bash
# `Enumerable#any?(& : T ->)` annotates its block without a return type, so
# each block supplies its own. V2 skipped the per-contract callback target
# for every annotated block param, so all `any?` calls on one receiver type
# shared the first block's yield type: a `Bool | Nil` block after a `Bool`
# one (or the reverse) read its result through the wrong slot and `any?`
# answered wrongly. Splitting the targets then exposed that the alias tail
# `__rawcb_<shape>_r<return>` was parsed as call argument types, losing the
# include-site `T = {Int32, Int32}` of `Iterator#each_with_index` and typing
# the block index as Pointer ("no overload matches Array#[]? (Pointer)").
# The compiler itself has the shape at
# `instruction.args.each_with_index.any? do |argument, index| ... end`.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/open-return-callback.XXXXXX")"

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

PRELUDE='class P
  getter type : Int32
  def initialize(@type : Int32)
  end
end
ps = [P.new(1), P.new(2), P.new(3)]
args = [10, 20]'

add_case nilable_block_first 'true|false' "$PRELUDE
STDERR.puts args.each.any? { |a| pa = ps[1]?; pa && pa.type == 2 }
STDERR.puts args.each.any? { |a| a == 7 }"

add_case bool_block_first 'false|true' "$PRELUDE
STDERR.puts args.each.any? { |a| a == 7 }
STDERR.puts args.each.any? { |a| pa = ps[1]?; pa && pa.type == 2 }"

add_case with_index_bool_block_first 'false|true' "$PRELUDE
STDERR.puts args.each_with_index.any? { |a, i| i == 7 }
STDERR.puts args.each_with_index.any? { |a, i| pa = ps[i]?; pa && pa.type == 2 }"

add_case with_index_mixed_blocks 'true|true|true|true|true|Bool|false|true|true' "$PRELUDE
STDERR.puts args.each_with_index.any? { |a, i| pa = ps[i]?; pa && pa.type == 2 }
STDERR.puts args.each_with_index.any? { |a, i| pa = ps[i]?; pa ? pa.type == 2 : false }
STDERR.puts args.each_with_index.any? { |a, i| pa = ps[i]; pa.type == 2 }
STDERR.puts args.any? { |a| pa = ps[1]?; pa && pa.type == 2 }
STDERR.puts args.each.any? { |a| pa = ps[1]?; pa && pa.type == 2 }
STDERR.puts typeof(args.each.any? { |a| pa = ps[1]?; pa && pa.type == 2 })
STDERR.puts [1].each.any? { |a| nil }
STDERR.puts [1].each.any? { |a| a == 1 ? P.new(1) : nil }
STDERR.puts [1].any? { |a| a == 1 ? P.new(1) : nil }"

add_case with_index_offset_then_map 'true|[10, 21]' "$PRELUDE
offset = ARGV.size
r = args.each_with_index.any? do |a, i|
  pa = ps[i + offset]?
  pa && pa.type == 2 && a == 20
end
STDERR.puts r
x = args.each_with_index.map { |a, i| a + i }.to_a
STDERR.puts x"

add_case int_elements 'false|true' '
ps = [1, 2, 3]
args = [10, 20]
STDERR.puts args.each_with_index.any? { |a, i| i == 7 }
STDERR.puts args.each_with_index.any? { |a, i| pa = ps[i]?; pa && pa == 2 }'

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
  printf '%d open-return callback case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all open-return callback cases passed\n'
