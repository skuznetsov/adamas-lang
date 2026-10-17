#!/usr/bin/env bash
# Preserve runtime Nil predicates on union carriers and exact-type neighbors.
set -euo pipefail

ADAMAS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PACKET_DIR="$ADAMAS_ROOT/regression_tests/fixtures/union_nil_predicate"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CANDIDATE_BIN="${1:-${ADAMAS_BIN:-$ADAMAS_ROOT/bin/adamas}}"
if [[ -z "$CANDIDATE_BIN" ]]; then
  printf 'usage: %s <candidate-compiler>\n' "$0" >&2
  exit 2
fi
SAFE_RUN="${SAFE_RUN:-$ADAMAS_ROOT/scripts/run_safe.sh}"
RUNS_ROOT="${RUNS_ROOT:-${TMPDIR:-/tmp}/union_nil_predicate_runs}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${RUN_MAX_MEM_MB:-512}"

for required in "$ORIGINAL_CRYSTAL_BIN" "$CANDIDATE_BIN" "$SAFE_RUN"; do
  if [[ ! -x "$required" ]]; then
    printf 'error: executable not found: %s\n' "$required" >&2
    exit 2
  fi
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
  local binary="$1"
  local timeout="$2"
  local memory="$3"
  shift 3
  "$SAFE_RUN" "$binary" "$timeout" "$memory" "$@"
}

cases=(
  runtime_union_nil
  runtime_union_non_nil
  disjoint_numeric_union
  exact_nil_int32_folds
  unless_runtime_union_non_nil
  nullable_reference
)
expected_for() {
  case "$1" in
    runtime_union_nil) printf '1\n' ;;
    runtime_union_non_nil) printf '2\n' ;;
    disjoint_numeric_union) printf '2\n' ;;
    exact_nil_int32_folds) printf '14\n' ;;
    unless_runtime_union_non_nil) printf '3\n' ;;
    nullable_reference) printf '1\n' ;;
    *) return 2 ;;
  esac
}

compile_and_run() {
  local stage="$1"
  local compiler="$2"
  local case_name="$3"
  local source="$PACKET_DIR/$case_name.cr"
  local binary="$RUN_DIR/$stage.$case_name"
  local cache_dir="$RUN_DIR/cache.$stage.$case_name"
  local expected="$RUN_DIR/$case_name.expected"
  local actual="$RUN_DIR/$stage.$case_name.stdout"
  mkdir -p "$cache_dir"
  expected_for "$case_name" >"$expected"

  if [[ "$stage" == original ]]; then
    if ! CRYSTAL_CACHE_DIR="$cache_dir" guarded "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --prelude=empty --no-debug --link-flags=-fuse-ld=/usr/bin/ld \
      "$source" -o "$binary" >"$RUN_DIR/$stage.$case_name.compile.log" 2>&1; then
      printf 'FAIL[%s/%s]: original compile failed; see %s\n' "$stage" "$case_name" "$RUN_DIR/$stage.$case_name.compile.log" >&2
      return 1
    fi
  else
    if ! CRYSTAL_CACHE_DIR="$cache_dir" guarded "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary" \
      >"$RUN_DIR/$stage.$case_name.compile.log" 2>&1; then
      printf 'FAIL[%s/%s]: candidate compile failed; see %s\n' "$stage" "$case_name" "$RUN_DIR/$stage.$case_name.compile.log" >&2
      return 1
    fi
  fi

  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 guarded "$binary" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" \
    >"$actual" 2>"$RUN_DIR/$stage.$case_name.run.log"; then
    printf 'FAIL[%s/%s]: runtime failed; see %s\n' "$stage" "$case_name" "$RUN_DIR/$stage.$case_name.run.log" >&2
    return 1
  fi
  if ! cmp "$expected" "$actual"; then
    printf 'FAIL[%s/%s]: expected output differs; see %s\n' "$stage" "$case_name" "$actual" >&2
    return 1
  fi
  printf 'PASS[%s/%s]\n' "$stage" "$case_name"
}

# Qualify the whole extension on original Crystal before compiling any candidate case.
for case_name in "${cases[@]}"; do
  compile_and_run original "$ORIGINAL_CRYSTAL_BIN" "$case_name"
done
printf 'ORIGINAL_NEIGHBORS_QUALIFIED=1\n'

for case_name in "${cases[@]}"; do
  compile_and_run candidate "$CANDIDATE_BIN" "$case_name"
  if ! cmp "$RUN_DIR/original.$case_name.stdout" "$RUN_DIR/candidate.$case_name.stdout"; then
    printf 'FAIL[candidate/%s]: output differs from original\n' "$case_name" >&2
    exit 1
  fi
done

printf 'PASS: Union Nil predicates and exact-type guards match original Crystal.\n'
