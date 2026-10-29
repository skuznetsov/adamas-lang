#!/usr/bin/env bash
# A zero-arg member call whose target is not lowered yet (`args.each_with_index`
# used as a call argument, or as the tail value, inside a class/struct body)
# took the name-shaped `Pointer` fallback before lower_function_if_needed and
# the force pass ran, and the guess suppressed that pass. The chained `any?`
# then resolved on Pointer (block index typed Pointer -> "no overload matches
# Array#[]? (Pointer)"). lower_call already deferred the guess; the member
# access path now defers it the same way.
# The compiler itself has the shape in AstToHir#repair_named_tuple_call_arguments.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/member-pointer-fallback.XXXXXX")"

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

add_case instance_arg_position 'true|false' '
class M
  def run(args : Array(UInt32)) : Nil
    STDERR.puts args.each_with_index.any? { |a, i| i > 0 }
    STDERR.puts args.each_with_index.any? { |a, i| i > 5 }
  end
end
M.new.run([5_u32, 6_u32])'

add_case class_method_arg_position 'true' '
class M
  def self.run(args : Array(UInt32)) : Nil
    STDERR.puts args.each_with_index.any? { |t| true }
  end
end
M.run([5_u32, 6_u32])'

add_case struct_arg_position 'false' '
struct S
  def run(args : Array(UInt32)) : Nil
    STDERR.puts args.each_with_index.any? { |a, i| a == 7 }
  end
end
S.new.run([5_u32, 6_u32])'

add_case tail_value_index_lookup 'true|false' '
class M
  def run(args : Array(UInt32), ps : Array(String), offset : Int32) : Bool
    args.each_with_index.any? do |argument, index|
      p = ps[index + offset]?
      p && argument > 5
    end
  end
end
STDERR.puts M.new.run([5_u32, 6_u32], ["a", "b", "c"], 1)
STDERR.puts M.new.run([5_u32, 4_u32], ["a", "b", "c"], 1)'

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
  printf '%d member pointer-fallback case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all member pointer-fallback cases passed\n'
