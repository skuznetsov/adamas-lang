#!/usr/bin/env bash
# Original-first regression for selected explicit return annotations.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ADAMAS_ROOT="${ADAMAS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-crystal}"
CANDIDATE_BIN="${1:-}"
if [[ -z "$CANDIDATE_BIN" || "$#" -ne 1 ]]; then
  printf 'usage: ORIGINAL_CRYSTAL_BIN=/path/to/pinned-crystal %s <candidate-adamas>\n' "$0" >&2
  exit 2
fi

SAFE_RUN="${SAFE_RUN:-$ADAMAS_ROOT/scripts/run_safe.sh}"
RUNS_ROOT="${RUNS_ROOT:-${TMPDIR:-/tmp}/selected_annotation_regression_runs}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${RUN_MAX_MEM_MB:-512}"
FIXTURE_NAMES=(selected_annotation_typeof selected_annotation_nilable_payload)

if [[ "$ORIGINAL_CRYSTAL_BIN" == */* ]]; then
  [[ -x "$ORIGINAL_CRYSTAL_BIN" ]] || { printf 'error: original compiler not executable: %s\n' "$ORIGINAL_CRYSTAL_BIN" >&2; exit 2; }
else
  command -v "$ORIGINAL_CRYSTAL_BIN" >/dev/null || { printf 'error: original compiler not found on PATH: %s\n' "$ORIGINAL_CRYSTAL_BIN" >&2; exit 2; }
fi
for required in "$CANDIDATE_BIN" "$SAFE_RUN"; do
  [[ -x "$required" ]] || { printf 'error: executable not found: %s\n' "$required" >&2; exit 2; }
done

mkdir -p "$RUNS_ROOT"
RUN_DIR="$(mktemp -d "$RUNS_ROOT/run.XXXXXX")"
printf 'run_dir=%s\n' "$RUN_DIR"
cleanup() {
  local status=$?
  trap - EXIT
  for cache_dir in "$RUN_DIR"/cache.*; do
    [[ -d "$cache_dir" ]] && rm -rf -- "$cache_dir"
  done
  if [[ "$status" == 0 ]]; then
    rm -rf -- "$RUN_DIR"
  else
    printf 'kept_artifacts=%s\n' "$RUN_DIR" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

guarded() {
  local binary="$1" timeout="$2" memory="$3"
  shift 3
  "$SAFE_RUN" "$binary" "$timeout" "$memory" "$@"
}

compile_and_check() {
  local stage="$1" compiler="$2" fixture="$3"
  local source="$SCRIPT_DIR/$fixture.cr"
  local expected="$SCRIPT_DIR/$fixture.expected"
  local cache="$RUN_DIR/cache.$stage.$fixture"
  local binary="$RUN_DIR/$stage.$fixture"
  mkdir -p "$cache"

  if [[ "$stage" == original ]]; then
    if ! CRYSTAL_CACHE_DIR="$cache" guarded "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" build --no-debug --link-flags=-fuse-ld=/usr/bin/ld "$source" -o "$binary" >"$RUN_DIR/$stage.$fixture.compile.log" 2>&1; then
      printf 'FAIL[%s/%s]: compile failed; see %s\n' "$stage" "$fixture" "$RUN_DIR/$stage.$fixture.compile.log" >&2
      return 1
    fi
  else
    if ! CRYSTAL_CACHE_DIR="$cache" guarded "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" "$source" -o "$binary" --no-debug --no-ast-cache --no-llvm-cache >"$RUN_DIR/$stage.$fixture.compile.log" 2>&1; then
      printf 'FAIL[%s/%s]: compile failed; see %s\n' "$stage" "$fixture" "$RUN_DIR/$stage.$fixture.compile.log" >&2
      return 1
    fi
  fi

  RUN_SAFE_PASSTHROUGH_STDIO=1 guarded "$binary" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$RUN_DIR/$stage.$fixture.stdout" 2>"$RUN_DIR/$stage.$fixture.run.log"
  if ! cmp -s "$expected" "$RUN_DIR/$stage.$fixture.stdout"; then
    printf 'FAIL[%s/%s]: output differs from the fixture oracle; see %s\n' "$stage" "$fixture" "$RUN_DIR/$stage.$fixture.stdout" >&2
    return 1
  fi
}

# Qualify every expected output on original Crystal before invoking Adamas.
for fixture in "${FIXTURE_NAMES[@]}"; do
  compile_and_check original "$ORIGINAL_CRYSTAL_BIN" "$fixture"
  printf 'ORIGINAL_QUALIFIED[%s]=1\n' "$fixture"
done

for fixture in "${FIXTURE_NAMES[@]}"; do
  compile_and_check candidate "$CANDIDATE_BIN" "$fixture"
  cmp "$RUN_DIR/original.$fixture.stdout" "$RUN_DIR/candidate.$fixture.stdout"
  printf 'PASS[%s]\n' "$fixture"
done
printf 'PASS: candidate matches original selected-annotation regression outputs.\n'
