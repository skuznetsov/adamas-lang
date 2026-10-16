#!/usr/bin/env bash
# Canonicalize Union(...) as a value set and retain admitted applied-generic
# variants through storage and bare generic parameter specialization.
# Compile invalid union arguments without executing them.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/canonical-generic-union.XXXXXX")"
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

cat >"$WORK_DIR/storage.cr" <<'CRYSTAL'
class UnionAdmissionState
end
struct UnionAdmissionContext(T)
  getter id : Int32
  def initialize(@value : T, @id : Int32)
  end
end
struct UnionAdmissionHolder(T)
  getter value : T
  def initialize(@value : T)
  end
end

def choose_union_context(flag : Bool)
  if flag
    UnionAdmissionContext(Nil).new(nil, 11)
  else
    UnionAdmissionContext(UnionAdmissionState).new(UnionAdmissionState.new, 22)
  end
end

def bare_context_id(context : UnionAdmissionContext)
  context.id
end

true_holder = UnionAdmissionHolder(Union(UnionAdmissionContext(Nil), UnionAdmissionContext(UnionAdmissionState))).new(choose_union_context(true))
false_holder = UnionAdmissionHolder(Union(UnionAdmissionContext(Nil), UnionAdmissionContext(UnionAdmissionState))).new(choose_union_context(false))
puts true_holder.value.id
puts false_holder.value.id
puts UnionAdmissionHolder(Union(Char, Char)).new('x').value.ord
puts UnionAdmissionHolder(Union(Char | Nil, Char)).new(nil).value.nil?
CRYSTAL

cat >"$WORK_DIR/storage.expected" <<'EXPECTED'
11
22
120
true
EXPECTED

cat >"$WORK_DIR/bare.cr" <<'CRYSTAL'
class UnionAdmissionState
end
struct UnionAdmissionContext(T)
  getter id : Int32
  def initialize(@value : T, @id : Int32)
  end
end
struct UnionAdmissionHolder(T)
  getter value : T
  def initialize(@value : T)
  end
end

def choose_union_context(flag : Bool)
  if flag
    UnionAdmissionContext(Nil).new(nil, 11)
  else
    UnionAdmissionContext(UnionAdmissionState).new(UnionAdmissionState.new, 22)
  end
end

def bare_context_id(context : UnionAdmissionContext)
  context.id
end

true_holder = UnionAdmissionHolder(Union(UnionAdmissionContext(Nil), UnionAdmissionContext(UnionAdmissionState))).new(choose_union_context(true))
false_holder = UnionAdmissionHolder(Union(UnionAdmissionContext(Nil), UnionAdmissionContext(UnionAdmissionState))).new(choose_union_context(false))
puts bare_context_id(true_holder.value)
puts bare_context_id(false_holder.value)
puts UnionAdmissionHolder(Union(Char, Char)).new('x').value.ord
puts UnionAdmissionHolder(Union(Char | Nil, Char)).new(nil).value.nil?
CRYSTAL

cat >"$WORK_DIR/bare.expected" <<'EXPECTED'
11
22
120
true
EXPECTED

cat >"$WORK_DIR/wrong_family.cr" <<'CRYSTAL'
class UnionAdmissionState; end
class UnionAdmissionOther
  def id; 99; end
end
struct UnionAdmissionContext(T)
  def initialize(@value : T); end
  def id; 11; end
end
def selected_union(flag : Bool)
  if flag
    UnionAdmissionContext(Nil).new(nil)
  else
    UnionAdmissionOther.new
  end
end
def restricted_union(value : UnionAdmissionContext)
  value.id
end
puts restricted_union(selected_union(false))
CRYSTAL

cat >"$WORK_DIR/wrong_argument.cr" <<'CRYSTAL'
class UnionAdmissionState; end
class UnionAdmissionOther
  def id; 99; end
end
struct UnionAdmissionContext(T)
  def initialize(@value : T); end
  def id; 11; end
end
def selected_union(flag : Bool)
  if flag
    UnionAdmissionContext(Nil).new(nil)
  else
    UnionAdmissionContext(UnionAdmissionState).new(UnionAdmissionState.new)
  end
end
def restricted_union(value : UnionAdmissionContext(Nil))
  value.id
end
puts restricted_union(selected_union(false))
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
      printf 'FAIL[%s/%s]: compiler admitted invalid union argument\n' "$stage" "$name" >&2
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
    if ! rg -qi 'error:.*(restricted_union|UnionAdmissionContext|no overload)' "$BUILD_LOG"; then
      printf 'FAIL[%s/%s]: expected a union restriction diagnostic\n' "$stage" "$name" >&2
      tail -20 "$BUILD_LOG" >&2
      FAILURES=$((FAILURES + 1))
      continue
    fi
    printf 'PASS[%s/%s/rejected]\n' "$stage" "$name"
  done
}

positive_case storage "$WORK_DIR/storage.expected"
positive_case bare "$WORK_DIR/bare.expected"
negative_case wrong_family
negative_case wrong_argument

if [[ "$FAILURES" -ne 0 ]]; then
  printf 'FAILED: %d canonical generic union check(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'PASS: canonical union storage and bare generic specialization match Crystal; unrelated and incompatible members reject\n'
