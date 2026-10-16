#!/usr/bin/env bash
# Infer bare generic class-method owners from each call, independently of
# earlier explicit specializations. Preserve source overload specificity.
# Compile invalid source restrictions without executing them.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bare-generic-class-method.XXXXXX")"
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

cat >"$WORK_DIR/owners.cr" <<'CRYSTAL'
class Carrier(T)
  getter value : T
  def initialize(@value : T)
  end
end
class SourceBox(T)
  def self.take(value : T)
    value
  end
  def self.from_carrier(value : Carrier(T))
    value.value
  end
end
class PairSource(A, B)
  def self.second(left : A, right : B)
    right
  end
end
puts SourceBox(Int32).take(7)
puts SourceBox.take("ok")
puts SourceBox.take(12_i64)
puts SourceBox.take("again")
puts SourceBox.from_carrier(Carrier(String).new("nested"))
puts PairSource(Int32, String).second(1, "explicit")
puts PairSource.second("left", 42_i64)
puts PairSource.second(2_i64, "right")
class SelectOwner(T)
  def self.choose(value : T)
    "broad"
  end
  def self.choose(value : Carrier(T))
    "nested"
  end
end
puts SelectOwner.choose(Carrier(String).new("ok"))
puts SelectOwner.choose("ok")

class ReverseSelectOwner(T)
  def self.choose(value : Carrier(T))
    "nested-reverse"
  end
  def self.choose(value : T)
    "broad-reverse"
  end
end
puts ReverseSelectOwner.choose(Carrier(String).new("ok"))
puts ReverseSelectOwner.choose("ok")
class DefaultOwner(T)
  def self.take(value : T, ignored : Int32 = 9)
    value
  end
end
puts DefaultOwner.take("default")
puts DefaultOwner.take(81_i64, 2)
class AmbientOwner(T)
  def self.read(value : String)
    SourceBox.take(value)
  end
end
puts AmbientOwner(Pointer(Void)).read("ambient")
CRYSTAL

cat >"$WORK_DIR/owners.expected" <<'EXPECTED'
7
ok
12
again
nested
explicit
42
right
nested
broad
nested-reverse
broad-reverse
default
81
ambient
EXPECTED

cat >"$WORK_DIR/wrong_family.cr" <<'CRYSTAL'
class RequiredCarrier(T)
  getter value : T
  def initialize(@value : T); end
end
class OtherCarrier(T)
  getter value : T
  def initialize(@value : T); end
end
class RequiredOwner(T)
  def self.read(value : RequiredCarrier(T))
    value.value
  end
end
puts RequiredOwner.read(OtherCarrier(String).new("wrong"))
CRYSTAL

cat >"$WORK_DIR/wrong_argument.cr" <<'CRYSTAL'
class RequiredCarrier(T)
  getter value : T
  def initialize(@value : T); end
end
class RequiredOwner(T)
  def self.read(value : RequiredCarrier(T))
    value.value
  end
end
puts RequiredOwner(Int32).read(RequiredCarrier(String).new("wrong"))
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
      printf 'FAIL[%s/%s]: compiler admitted invalid owner restriction\n' "$stage" "$name" >&2
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
    if ! rg -qi 'error:.*(RequiredOwner|RequiredCarrier|no overload|cannot infer)' "$BUILD_LOG"; then
      printf 'FAIL[%s/%s]: expected an owner restriction diagnostic\n' "$stage" "$name" >&2
      tail -20 "$BUILD_LOG" >&2
      FAILURES=$((FAILURES + 1))
      continue
    fi
    printf 'PASS[%s/%s/rejected]\n' "$stage" "$name"
  done
}

positive_case owners "$WORK_DIR/owners.expected"
negative_case wrong_family
negative_case wrong_argument

if [[ "$FAILURES" -ne 0 ]]; then
  printf 'FAILED: %d bare generic class-method check(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'PASS: bare generic class-method inference matches Crystal on 15 native outputs; invalid source restrictions reject\n'
