#!/usr/bin/env bash
# Admit all scalar union arms against their source overloads before CFG emission.
# Deferred exact targets must retain declaration context and match their final ABI.
# Keep mixed-return dispatch separate from union-valued stdio formatting.
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${COMPILER:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-}"

if [[ ! -x "$SAFE_RUN" || ! -x "$COMPILER" || ! -x "$ORIGINAL_CRYSTAL_BIN" ]]; then
  echo "ERROR: set ROOT_DIR, COMPILER, and ORIGINAL_CRYSTAL_BIN to executable paths" >&2
  exit 2
fi
if [[ -n "$CRYSTAL_STDLIB" && ! -d "$CRYSTAL_STDLIB" ]]; then
  echo "ERROR: CRYSTAL_PATH is not a directory: $CRYSTAL_STDLIB" >&2
  exit 2
fi

if [[ -n "${LLVM_ROOT:-}" ]]; then
  PATH="$LLVM_ROOT/bin:$PATH"
  CRYSTAL_LIBRARY_PATH="$LLVM_ROOT/lib${CRYSTAL_LIBRARY_PATH:+:$CRYSTAL_LIBRARY_PATH}"
  export PATH CRYSTAL_LIBRARY_PATH
fi
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
export ADAMAS_LLVM_CACHE="${ADAMAS_LLVM_CACHE:-0}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union-argument-admission.XXXXXX")"
FAILURES=0
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "$FAILURES" -ne 0 || "${KEEP_ARTIFACTS:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/matrix.cr" <<'CRYSTAL'
class ForwardDispatcher
  def pick(value : String); "string"; end
  def pick(value : Array(String)); "array"; end
end
class ReverseDispatcher
  def pick(value : Array(String)); "reverse-array"; end
  def pick(value : String); "reverse-string"; end
end
def string_or_array(flag : Bool)
  flag ? "text" : ["entry"]
end
forward = ForwardDispatcher.new
reverse = ReverseDispatcher.new
puts forward.pick(string_or_array(true))
puts forward.pick(string_or_array(false))
puts reverse.pick(string_or_array(true))
puts reverse.pick(string_or_array(false))

class NullableDispatcher
  def pick(value : String); "nullable-string"; end
  def pick(value : Array(String)); "nullable-array"; end
  def pick(value : Nil); "nullable-nil"; end
end
def three_values(index : Int32)
  case index
  when 0 then "text"
  when 1 then ["entry"]
  else nil
  end
end
nullable = NullableDispatcher.new
puts nullable.pick(three_values(0))
puts nullable.pick(three_values(1))
puts nullable.pick(three_values(2))

class ReturnDispatcher
  def pick(value : String); 17_i64; end
  def pick(value : Array(String)); "return-array"; end
end
returns = ReturnDispatcher.new
def describe_return(value : Int64 | String)
  if value.is_a?(Int64)
    value == 17_i64 ? "return-int" : "wrong-int"
  else
    value == "return-array" ? "return-array" : "wrong-string"
  end
end
puts describe_return(returns.pick(string_or_array(true)))
puts describe_return(returns.pick(string_or_array(false)))

class InheritedDispatcher
  def pick(value : String); "inherited-string"; end
end
class DerivedDispatcher < InheritedDispatcher
  def pick(value : Array(String)); "derived-array"; end
end
derived = DerivedDispatcher.new
puts derived.pick(string_or_array(true))
puts derived.pick(string_or_array(false))

class SourceCounter
  getter count : Int32 = 0
  def next_value(flag : Bool)
    @count += 1
    string_or_array(flag)
  end
end
counter = SourceCounter.new
puts forward.pick(counter.next_value(true))
puts counter.count
puts forward.pick(counter.next_value(false))
puts counter.count

class Envelope(T)
  getter value : T
  def initialize(@value : T); end
end
class GenericDispatcher
  def pick(value : Envelope(String)); "generic-string"; end
  def pick(value : Envelope(Int32)); "generic-int"; end
end
def generic_value(flag : Bool)
  flag ? Envelope(String).new("text") : Envelope(Int32).new(7)
end
generic = GenericDispatcher.new
puts generic.pick(generic_value(true))
puts generic.pick(generic_value(false))
CRYSTAL

cat >"$WORK_DIR/matrix.expected" <<'EXPECTED'
string
array
reverse-string
reverse-array
nullable-string
nullable-array
nullable-nil
return-int
return-array
inherited-string
derived-array
string
1
array
2
generic-string
generic-int
EXPECTED

cat >"$WORK_DIR/inline_fetch.cr" <<'CRYSTAL'
class InlineDispatcher
  private def concat(value : String)
    value
  end
  private def concat(value : Array(String))
    "array"
  end
  def fetch(index : Int32, &)
    value = case index
            when 0 then "string"
            when 1 then ["array"]
            else nil
            end
    value ? concat(value) : yield index
  end
  def read(index : Int32)
    fetch(index) { "absent" }
  end
end
reader = InlineDispatcher.new
puts reader.read(0)
puts reader.read(1)
puts reader.read(2)
CRYSTAL

cat >"$WORK_DIR/inline_fetch.expected" <<'EXPECTED'
string
array
absent
EXPECTED

cat >"$WORK_DIR/generic_inline_fetch.cr" <<'CRYSTAL'
class ScopedInlineDispatcher(T)
  def initialize(@first : T, @second : Array(T)); end
  private def concat(value : T)
    "scalar"
  end
  private def concat(value : Array(T))
    "array"
  end
  def fetch(index : Int32, &)
    value = case index
            when 0 then @first
            when 1 then @second
            else nil
            end
    value ? concat(value) : yield index
  end
  def read(index : Int32)
    fetch(index) { "absent" }
  end
end
strings = ScopedInlineDispatcher(String).new("entry", ["entry"])
puts strings.read(0)
puts strings.read(1)
puts strings.read(2)
numbers = ScopedInlineDispatcher(Int32).new(7, [7])
puts numbers.read(0)
puts numbers.read(1)
puts numbers.read(2)
CRYSTAL

cat >"$WORK_DIR/generic_inline_fetch.expected" <<'EXPECTED'
scalar
array
absent
scalar
array
absent
EXPECTED

cat >"$WORK_DIR/uncovered.cr" <<'CRYSTAL'
class PartialDispatcher
  def pick(value : String); "string"; end
  def pick(value : Array(String)); "array"; end
end
def uncovered_value(index : Int32)
  case index
  when 0 then "text"
  when 1 then ["entry"]
  else 7
  end
end
puts PartialDispatcher.new.pick(uncovered_value(0))
CRYSTAL

compile_case() {
  local stage="$1" name="$2" source="$3"
  local cache="$WORK_DIR/cache_${stage}_${name}"
  local log="$WORK_DIR/${stage}_${name}.build.log"
  local binary="$WORK_DIR/${stage}_${name}.bin"
  local status=0
  mkdir -p "$cache"

  if [[ "$stage" == "original" ]]; then
    if [[ -n "$CRYSTAL_STDLIB" ]]; then
      CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${stage}_${name}.build.resources" \
        "$SAFE_RUN" "$ORIGINAL_CRYSTAL_BIN" 240 8192 build "$source" \
        --no-debug --error-trace -o "$binary" \
        --link-flags=-fuse-ld=/usr/bin/ld >"$log" 2>&1 || status=$?
    else
      CRYSTAL_CACHE_DIR="$cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${stage}_${name}.build.resources" \
        "$SAFE_RUN" "$ORIGINAL_CRYSTAL_BIN" 240 8192 build "$source" \
        --no-debug --error-trace -o "$binary" \
        --link-flags=-fuse-ld=/usr/bin/ld >"$log" 2>&1 || status=$?
    fi
  else
    if [[ -n "$CRYSTAL_STDLIB" ]]; then
      CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${stage}_${name}.build.resources" \
        "$SAFE_RUN" "$COMPILER" 240 8192 "$source" \
        --no-ast-cache --no-llvm-cache --no-debug -o "$binary" \
        >"$log" 2>&1 || status=$?
    else
      CRYSTAL_CACHE_DIR="$cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${stage}_${name}.build.resources" \
        "$SAFE_RUN" "$COMPILER" 240 8192 "$source" \
        --no-ast-cache --no-llvm-cache --no-debug -o "$binary" \
        >"$log" 2>&1 || status=$?
    fi
  fi

  # Crystal and Adamas caches are disposable for each isolated compile.
  python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$cache"
  BUILD_STATUS="$status"
  BUILD_LOG="$log"
  BUILD_BINARY="$binary"
}

run_case() {
  local stage="$1" name="$2" binary="$3"
  local output="$WORK_DIR/${stage}_${name}.stdout"
  local log="$WORK_DIR/${stage}_${name}.run.log"
  local status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${stage}_${name}.run.resources" \
    "$SAFE_RUN" "$binary" 20 1024 >"$output" 2>"$log" || status=$?
  RUN_STATUS="$status"
  RUN_OUTPUT="$output"
  RUN_LOG="$log"
}

positive_case() {
  local name="$1" expected="$2" stage
  for stage in original candidate; do
    compile_case "$stage" "$name" "$WORK_DIR/$name.cr"
    if [[ "$BUILD_STATUS" -ne 0 ]]; then
      printf 'FAIL[%s/%s]: compilation failed\n' "$stage" "$name" >&2
      tail -20 "$BUILD_LOG" >&2
      FAILURES=$((FAILURES + 1))
      continue
    fi
    run_case "$stage" "$name" "$BUILD_BINARY"
    if [[ "$RUN_STATUS" -ne 0 ]] || ! diff -u "$expected" "$RUN_OUTPUT" >&2; then
      printf 'FAIL[%s/%s]: runtime output differed from the expected result\n' "$stage" "$name" >&2
      tail -20 "$RUN_LOG" >&2
      FAILURES=$((FAILURES + 1))
      continue
    fi
    printf 'PASS[%s/%s]\n' "$stage" "$name"
  done
  if [[ -f "$WORK_DIR/original_${name}.stdout" &&
        -f "$WORK_DIR/candidate_${name}.stdout" ]] &&
      ! diff -u "$WORK_DIR/original_${name}.stdout" \
        "$WORK_DIR/candidate_${name}.stdout" >&2; then
    printf 'FAIL[%s]: original and candidate outputs differ\n' "$name" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

negative_case() {
  local name="$1" stage
  for stage in original candidate; do
    compile_case "$stage" "$name" "$WORK_DIR/$name.cr"
    if [[ "$BUILD_STATUS" -eq 0 || -e "$BUILD_BINARY" ]]; then
      printf 'FAIL[%s/%s]: compiler admitted an uncovered union arm\n' "$stage" "$name" >&2
      FAILURES=$((FAILURES + 1))
      continue
    fi
    case "$BUILD_STATUS" in
      124|134|137|139|143)
        printf 'FAIL[%s/%s]: abnormal compiler termination: %s\n' "$stage" "$name" "$BUILD_STATUS" >&2
        tail -20 "$BUILD_LOG" >&2
        FAILURES=$((FAILURES + 1))
        continue
        ;;
    esac
    if ! rg -qi 'error:.*(PartialDispatcher|no overload|expected argument)' "$BUILD_LOG"; then
      printf 'FAIL[%s/%s]: expected a source overload rejection diagnostic\n' "$stage" "$name" >&2
      tail -20 "$BUILD_LOG" >&2
      FAILURES=$((FAILURES + 1))
      continue
    fi
    printf 'PASS[%s/%s/rejected]\n' "$stage" "$name"
  done
}

positive_case matrix "$WORK_DIR/matrix.expected"
positive_case inline_fetch "$WORK_DIR/inline_fetch.expected"
positive_case generic_inline_fetch "$WORK_DIR/generic_inline_fetch.expected"
negative_case uncovered

if [[ "$FAILURES" -ne 0 ]]; then
  printf 'FAILED: %d union argument source-admission check(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'PASS: union argument source admission matches Crystal on 26 native outputs; uncovered arms reject\n'
