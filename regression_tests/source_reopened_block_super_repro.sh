#!/usr/bin/env bash
# Reopened module block-super lookup must select the newest compatible Def.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/source-reopened-block-super.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

if [[ ! -x "$SAFE" || ! -x "$COMPILER" ]]; then
  echo "ERROR: set ADAMAS_BIN to an executable compiler" >&2
  exit 2
fi

compile_and_run() {
  local mode="$1" fixture="$2" expected="$3" status=0
  local source="$FIXTURES/$fixture.cr"
  local output="$WORK/$mode-$fixture.bin"
  local log="$WORK/$mode-$fixture.compile.log"
  local stdout="$WORK/$mode-$fixture.stdout"
  local run_log="$WORK/$mode-$fixture.run.log"
  local -a command_args mode_env

  if [[ "$mode" == stock ]]; then
    [[ -n "$ORIGINAL" && -x "$ORIGINAL" ]] || return 0
    command_args=("$ORIGINAL" 120 4096 build --prelude=empty --no-debug)
    if [[ "$(uname -s)" == Darwin ]]; then
      command_args+=(--link-flags=-fuse-ld=/usr/bin/ld)
    fi
    CRYSTAL_CACHE_DIR="$WORK/cache.stock" \
      "$SAFE" "${command_args[@]}" "$source" -o "$output" >"$log" 2>&1 || status=$?
  else
    command_args=("$COMPILER" 120 4096 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
    if [[ "$mode" == eager ]]; then
      mode_env=(env ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 ADAMAS_LLVM_CACHE=0)
    else
      mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO ADAMAS_LLVM_CACHE=0)
    fi
    CRYSTAL_CACHE_DIR="$WORK/cache.$mode" \
      "${mode_env[@]}" "$SAFE" "${command_args[@]}" "$source" -o "$output" >"$log" 2>&1 || status=$?
  fi

  if [[ "$status" != 0 ]]; then
    cat "$log" >&2
    printf 'FAIL[%s]: compile %s\n' "$mode" "$fixture" >&2
    return 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 >"$stdout" 2>"$run_log" || {
    cat "$run_log" "$stdout" >&2
    printf 'FAIL[%s]: run %s\n' "$mode" "$fixture" >&2
    return 1
  }
  cmp "$FIXTURES/$expected" "$stdout" || {
    printf 'FAIL[%s]: output mismatch for %s\n' "$mode" "$fixture" >&2
    return 1
  }
  printf 'PASS[%s]: %s\n' "$mode" "$fixture"
}

for fixture in source_reopened_block_super source_reopened_block_super_shape_control; do
  expected="$fixture.expected"
  if [[ -n "$ORIGINAL" && -x "$ORIGINAL" ]]; then
    compile_and_run stock "$fixture" "$expected"
  else
    printf 'SKIP[stock]: crystal executable not found\n'
  fi
  compile_and_run lazy "$fixture" "$expected"
  compile_and_run eager "$fixture" "$expected"
done
