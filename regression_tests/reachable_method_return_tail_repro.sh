#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  printf 'usage: %s [candidate-adamas]\n' "$0" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
candidate_root="$ROOT"
packet_dir="$ROOT/spec/fixtures/reachable_method_tail"
CANDIDATE="${1:-$ROOT/bin/adamas}"
[[ -x "$CANDIDATE" ]] || { printf 'error: missing candidate compiler: %s\n' "$CANDIDATE" >&2; exit 2; }
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
if [[ -z "$ORIGINAL_CRYSTAL_BIN" ]]; then
  printf 'error: set ORIGINAL_CRYSTAL_BIN to the pinned original Crystal executable\n' >&2
  exit 2
fi
if [[ "$ORIGINAL_CRYSTAL_BIN" == */* ]]; then
  [[ -x "$ORIGINAL_CRYSTAL_BIN" ]] || { printf 'error: original Crystal is not executable: %s\n' "$ORIGINAL_CRYSTAL_BIN" >&2; exit 2; }
else
  command -v "$ORIGINAL_CRYSTAL_BIN" >/dev/null || { printf 'error: original Crystal not found: %s\n' "$ORIGINAL_CRYSTAL_BIN" >&2; exit 2; }
fi

SAFE_RUN="${SAFE_RUN:-${ADAMAS_ROOT:-$candidate_root}/scripts/run_safe.sh}"
[[ -x "$SAFE_RUN" ]] || { printf 'error: run_safe.sh is not executable: %s\n' "$SAFE_RUN" >&2; exit 2; }
[[ -d "$candidate_root/src/compiler/hir" ]] || { printf 'error: candidate source root is missing src/compiler/hir: %s\n' "$candidate_root" >&2; exit 2; }

# Preserve the caller's pinned original stdlib path. If it was not set in the
# environment, ask the selected Crystal binary under run_safe's limits.
ORIGINAL_CRYSTAL_PATH="${PRISTINE_CRYSTAL_PATH:-${CRYSTAL_PATH:-}}"
RUNS_ROOT="${RUNS_ROOT:-${TMPDIR:-/tmp}/reachable_method_return_tail_runs}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-90}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-10}"
RUN_MAX_MEM_MB="${RUN_MAX_MEM_MB:-1024}"

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

if [[ -z "$ORIGINAL_CRYSTAL_PATH" ]]; then
  mkdir -p "$RUN_DIR/cache.env"
  if ! CRYSTAL_CACHE_DIR="$RUN_DIR/cache.env" RUN_SAFE_PASSTHROUGH_STDIO=1 \
    guarded "$ORIGINAL_CRYSTAL_BIN" 10 1024 env CRYSTAL_PATH \
    >"$RUN_DIR/original_crystal_path" 2>"$RUN_DIR/original_crystal_path.log"; then
    printf 'error: could not read pinned original CRYSTAL_PATH; see %s\n' "$RUN_DIR/original_crystal_path.log" >&2
    exit 1
  fi
  ORIGINAL_CRYSTAL_PATH="$(cat "$RUN_DIR/original_crystal_path")"
fi
if [[ -z "$ORIGINAL_CRYSTAL_PATH" ]]; then
  printf 'error: original Crystal path is empty; set PRISTINE_CRYSTAL_PATH or CRYSTAL_PATH\n' >&2
  exit 2
fi
export CRYSTAL_PATH="$ORIGINAL_CRYSTAL_PATH"

ORIGINAL_LINK_FLAGS="${ORIGINAL_LINK_FLAGS:-${ADAMAS_ORIGINAL_LINK_FLAGS:-${CRYSTAL_LINK_FLAGS:-}}}"
if [[ -z "$ORIGINAL_LINK_FLAGS" && "$(uname -s)" == Darwin ]]; then
  ORIGINAL_LINK_FLAGS="-fuse-ld=/usr/bin/ld"
fi
original_link_args=()
[[ -z "$ORIGINAL_LINK_FLAGS" ]] || original_link_args+=("--link-flags=$ORIGINAL_LINK_FLAGS")

compile_original_and_run() {
  local label="$1" source="$2" expected="$3" crystal_path="$4"
  local cache="$RUN_DIR/cache.$label"
  local binary="$RUN_DIR/$label"
  mkdir -p "$cache"

  if ! CRYSTAL_PATH="$crystal_path" CRYSTAL_CACHE_DIR="$cache" \
    guarded "$ORIGINAL_CRYSTAL_BIN" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --no-debug "${original_link_args[@]}" "$source" -o "$binary" \
      >"$RUN_DIR/$label.compile.log" 2>&1; then
    printf 'FAIL[%s]: original Crystal compile failed; see %s\n' "$label" "$RUN_DIR/$label.compile.log" >&2
    return 1
  fi

  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 guarded "$binary" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" \
    >"$RUN_DIR/$label.stdout" 2>"$RUN_DIR/$label.run.log"; then
    printf 'FAIL[%s]: run_safe execution failed; see %s\n' "$label" "$RUN_DIR/$label.run.log" >&2
    return 1
  fi
  if [[ "$expected" != "-" ]]; then
    if ! cmp -s "$expected" "$RUN_DIR/$label.stdout"; then
      printf 'FAIL[%s]: output differs from its oracle; see %s\n' "$label" "$RUN_DIR/$label.stdout" >&2
      return 1
    fi
  fi
}

# Establish the language-level typeof contract before testing candidate HIR.
compile_original_and_run \
  original_type_oracle \
  "$packet_dir/reachable_method_tail_type_oracle.cr" \
  "$packet_dir/reachable_method_tail_type_oracle.expected" \
  "$ORIGINAL_CRYSTAL_PATH"
printf 'ORIGINAL_TYPE_ORACLE=8/8\n'

# The HIR spec is compiled by original Crystal while loading the candidate
# compiler sources first and retaining the same pinned original stdlib path.
candidate_crystal_path="$candidate_root/src:$ORIGINAL_CRYSTAL_PATH"
compile_original_and_run \
  candidate_hir_spec \
  "$ROOT/spec/hir/reachable_method_return_tail_spec.cr" \
  - \
  "$candidate_crystal_path"
printf 'PASS: candidate HIR return-tail assertions passed under original Crystal.\n'

# Exercise each native branch as well as the HIR type contract. The candidate
# compiler must be built from this source state; callers may pass its exact path.
compile_original_and_run \
  original_native_branches \
  "$packet_dir/explicit_return_fallthrough.cr" \
  "$packet_dir/explicit_return_fallthrough.expected" \
  "$ORIGINAL_CRYSTAL_PATH"
if ! CRYSTAL_PATH="$ORIGINAL_CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$RUN_DIR/cache.candidate_native" \
  ADAMAS_LLVM_CACHE=0 guarded "$CANDIDATE" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
    "$packet_dir/explicit_return_fallthrough.cr" --no-debug --no-ast-cache --no-llvm-cache \
    -o "$RUN_DIR/candidate_native" >"$RUN_DIR/candidate_native.compile.log" 2>&1; then
  printf 'FAIL: candidate native branch compilation; see %s\n' "$RUN_DIR/candidate_native.compile.log" >&2
  exit 1
fi
if ! RUN_SAFE_PASSTHROUGH_STDIO=1 guarded "$RUN_DIR/candidate_native" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" \
  >"$RUN_DIR/candidate_native.stdout" 2>"$RUN_DIR/candidate_native.run.log"; then
  printf 'FAIL: candidate native branch execution; see %s\n' "$RUN_DIR/candidate_native.run.log" >&2
  exit 1
fi
cmp "$packet_dir/explicit_return_fallthrough.expected" "$RUN_DIR/candidate_native.stdout"
printf 'PASS: 18 native return-branch outputs match original Crystal.\n'
