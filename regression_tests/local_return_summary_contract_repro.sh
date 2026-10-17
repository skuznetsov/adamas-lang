#!/usr/bin/env bash
# Original-first no-prelude contract for speculative local return summaries.
set -euo pipefail

PACKET_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CANDIDATE_BIN="${1:-}"
if [[ -z "$CANDIDATE_BIN" ]]; then
  printf 'usage: %s <candidate-adamas-bin>\n' "$0" >&2
  exit 2
fi
if [[ "$CANDIDATE_BIN" != */* ]]; then CANDIDATE_BIN="$(command -v "$CANDIDATE_BIN" || true)"; fi
if [[ -z "$CANDIDATE_BIN" || ! -x "$CANDIDATE_BIN" ]]; then
  printf 'error: candidate compiler is not executable: %s\n' "${1:-}" >&2
  exit 2
fi

find_adamas_root() {
  local probe="$1"
  while [[ "$probe" != / ]]; do
    if [[ -x "$probe/scripts/run_safe.sh" ]]; then printf '%s\n' "$probe"; return 0; fi
    probe="$(dirname "$probe")"
  done
  return 1
}
if [[ -z "${ADAMAS_ROOT:-}" ]]; then
  ADAMAS_ROOT="$(find_adamas_root "$PACKET_DIR")" || {
    candidate_dir="$(cd "$(dirname "$CANDIDATE_BIN")" && pwd -P)"
    ADAMAS_ROOT="$(find_adamas_root "$candidate_dir")" || {
      printf 'error: set ADAMAS_ROOT or run from an Adamas checkout\n' >&2
      exit 2
    }
  }
fi
SAFE_RUN="${SAFE_RUN:-$ADAMAS_ROOT/scripts/run_safe.sh}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
if [[ -z "$ORIGINAL_CRYSTAL_BIN" ]]; then
  printf 'error: set ORIGINAL_CRYSTAL_BIN or put pinned original Crystal on PATH as crystal\n' >&2
  exit 2
fi
for required in "$ORIGINAL_CRYSTAL_BIN" "$SAFE_RUN"; do
  if [[ ! -x "$required" ]]; then printf 'error: executable not found: %s\n' "$required" >&2; exit 2; fi
done

RUNS_ROOT="${RUNS_ROOT:-${TMPDIR:-/tmp}/local_return_summary_contract_runs}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${RUN_MAX_MEM_MB:-512}"
case_names=(lazy_bare lazy_parenthesized assigned_every_path initialized_before_if exhaustive_branches terminated_branch recursive_local_return loop_local_return)
mkdir -p "$RUNS_ROOT"
RUN_DIR="$(mktemp -d "$RUNS_ROOT/run.XXXXXX")"
printf 'run_dir=%s\n' "$RUN_DIR"
cleanup() {
  local status=$?
  trap - EXIT
  for cache_dir in "$RUN_DIR"/cache.*; do [[ -d "$cache_dir" ]] && rm -rf -- "$cache_dir"; done
  if [[ "$status" == 0 ]]; then rm -rf -- "$RUN_DIR"; else printf 'kept_artifacts=%s\n' "$RUN_DIR" >&2; fi
  exit "$status"
}
trap cleanup EXIT

guarded() { local binary="$1" timeout="$2" memory="$3"; shift 3; "$SAFE_RUN" "$binary" "$timeout" "$memory" "$@"; }
compile_and_run() {
  local stage="$1" compiler="$2" case_name="$3"
  local source="$PACKET_DIR/fixtures/local_return_summary_contract_${case_name}.cr"
  local expected="$PACKET_DIR/expected/local_return_summary_contract_${case_name}.stdout"
  local binary="$RUN_DIR/$stage.$case_name" cache_dir="$RUN_DIR/cache.$stage.$case_name"
  local compile_log="$RUN_DIR/$stage.$case_name.compile.log"
  local actual="$RUN_DIR/$stage.$case_name.stdout"
  mkdir -p "$cache_dir"
  if [[ "$stage" == original ]]; then
    if ! CRYSTAL_CACHE_DIR="$cache_dir" guarded "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --prelude=empty --no-debug "$source" -o "$binary" >"$compile_log" 2>&1; then
      printf 'FAIL[%s/%s]: compile failed; see %s\n' "$stage" "$case_name" "$compile_log" >&2; return 1
    fi
  else
    if ! CRYSTAL_CACHE_DIR="$cache_dir" guarded "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary" >"$compile_log" 2>&1; then
      printf 'FAIL[%s/%s]: compile failed; see %s\n' "$stage" "$case_name" "$compile_log" >&2; return 1
    fi
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 guarded "$binary" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$actual" 2>"$RUN_DIR/$stage.$case_name.run.log"; then
    printf 'FAIL[%s/%s]: runtime failed; see %s\n' "$stage" "$case_name" "$RUN_DIR/$stage.$case_name.run.log" >&2; return 1
  fi
  if ! cmp "$expected" "$actual"; then printf 'FAIL[%s/%s]: expected stdout differs; see %s\n' "$stage" "$case_name" "$actual" >&2; return 1; fi
  printf 'PASS[%s/%s]\n' "$stage" "$case_name"
}
for case_name in "${case_names[@]}"; do compile_and_run original "$ORIGINAL_CRYSTAL_BIN" "$case_name"; done
printf 'ORIGINAL_QUALIFIED=1\n'
for case_name in "${case_names[@]}"; do compile_and_run candidate "$CANDIDATE_BIN" "$case_name"; done
for case_name in "${case_names[@]}"; do cmp "$RUN_DIR/original.$case_name.stdout" "$RUN_DIR/candidate.$case_name.stdout"; done
printf 'PASS: candidate matches original across lazy reads and assignment, branch, recursion, and loop controls.\n'
