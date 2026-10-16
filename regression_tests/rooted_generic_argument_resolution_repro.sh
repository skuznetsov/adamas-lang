#!/usr/bin/env bash
# Keep leading :: qualification inside generic arguments during contextual
# resolution, even when a same-name local module shadows the root declaration.
# Compare behavior with the pinned/or selected upstream Crystal compiler.
#
# Usage:
#   ORIGINAL_CRYSTAL_BIN=/path/to/crystal CRYSTAL_PATH=/path/to/crystal/src \
#     bash regression_tests/rooted_generic_argument_resolution_repro.sh /path/to/adamas
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rooted-generic-arguments.XXXXXX")"
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

cat >"$WORK_DIR/rooted_shadow.cr" <<'CRYSTAL'
module AdmissionView
end

class AdmissionRootImpl
  include ::AdmissionView
end

module AdmissionScope
  # This same-name declaration must not absorb the absolute argument below.
  module AdmissionView
  end

  class RootImpl
    include ::AdmissionView
  end

  def self.accept_root(values : Array(::AdmissionView)) : Int32
    values.size + 20
  end

  # Exercise absolute-name retention in a nested generic argument as well.
  def self.accept_nested(values : Array(Array(::AdmissionView))) : Int32
    values[0].size + 40
  end
end

def accept_global(values : Array(AdmissionView)) : Int32
  values.size + 30
end

puts accept_global([AdmissionRootImpl.new])
puts AdmissionScope.accept_root([AdmissionScope::RootImpl.new])
puts AdmissionScope.accept_nested([[AdmissionScope::RootImpl.new]])
CRYSTAL

cat >"$WORK_DIR/local_only.cr" <<'CRYSTAL'
module AdmissionScope
  module AdmissionView
  end

  class LocalImpl
    include AdmissionView
  end

  def self.accept_local(values : Array(AdmissionView)) : Int32
    values.size + 10
  end
end

puts AdmissionScope.accept_local([AdmissionScope::LocalImpl.new])
CRYSTAL

cat >"$WORK_DIR/top_level_only.cr" <<'CRYSTAL'
module AdmissionView
end

class AdmissionRootImpl
  include AdmissionView
end

def accept_global(values : Array(AdmissionView)) : Int32
  values.size + 30
end

puts accept_global([AdmissionRootImpl.new])
CRYSTAL

cat >"$WORK_DIR/wrong_namespace.cr" <<'CRYSTAL'
module AdmissionView
end

module Other
  module AdmissionView
  end
end

class OtherImpl
  include Other::AdmissionView
end

module AdmissionScope
  module AdmissionView
  end

  def self.accept_wrong(values : Array(::AdmissionView)) : Int32
    values.size
  end
end

AdmissionScope.accept_wrong([OtherImpl.new])
CRYSTAL

printf '31\n21\n41\n' >"$WORK_DIR/rooted_shadow.expected"
printf '11\n' >"$WORK_DIR/local_only.expected"
printf '31\n' >"$WORK_DIR/top_level_only.expected"

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
  local stage
  for stage in original candidate; do
    compile_case "$stage" wrong_namespace "$WORK_DIR/wrong_namespace.cr"
    if [[ "$BUILD_STATUS" -eq 0 ]]; then
      printf 'FAIL[%s/wrong_namespace]: unrelated namespace was accepted\n' "$stage" >&2
      FAILURES=$((FAILURES + 1))
      continue
    fi
    if ! grep -Eiq 'Error: (expected argument|no overload matches)' "$BUILD_LOG" ||
       ! grep -Fq 'AdmissionView' "$BUILD_LOG" ||
       ! grep -Fq 'OtherImpl' "$BUILD_LOG" ||
       grep -Eiq 'SIGBUS|SIGSEGV|Bus error|Segmentation fault|stack overflow|signal [0-9]+' "$BUILD_LOG"; then
      printf 'FAIL[%s/wrong_namespace]: rejection was not a source type mismatch\n' "$stage" >&2
      tail -20 "$BUILD_LOG" >&2
      FAILURES=$((FAILURES + 1))
      continue
    fi
    printf 'PASS[%s/wrong_namespace]: rejected unrelated namespace\n' "$stage"
  done
}

positive_case rooted_shadow "$WORK_DIR/rooted_shadow.expected"
positive_case local_only "$WORK_DIR/local_only.expected"
positive_case top_level_only "$WORK_DIR/top_level_only.expected"
negative_case

if [[ "$FAILURES" -ne 0 ]]; then
  printf 'FAILED: %d rooted generic argument check(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'PASS: absolute generic arguments, nested generic arguments, lexical shadowing, and wrong-namespace rejection match Crystal\n'
