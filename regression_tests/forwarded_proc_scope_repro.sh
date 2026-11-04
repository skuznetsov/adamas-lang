#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$ROOT/regression_tests/fixtures/forwarded_proc_scope/branches.cr"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-forwarded-proc-scope.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
if [[ "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

printf AECEDE >"$WORK/expected"
for mode in stock lazy eager; do
  unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
  if [[ "$mode" == eager ]]; then
    export ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1
  fi
  output="$WORK/$mode.bin"
  if [[ "$mode" == stock ]]; then
    command=("$CRYSTAL" build "$SOURCE" --prelude=empty --no-debug -o "$output")
  else
    command=("$ADAMAS" "$SOURCE" --prelude=empty --no-debug --no-ast-cache --no-llvm-cache -o "$output")
  fi
  if ! "$SAFE" "${command[0]}" 90 8192 "${command[@]:1}" >"$output.compile.log" 2>&1; then
    cat "$output.compile.log" >&2
    exit 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 >"$output.stdout"
  diff -u "$WORK/expected" "$output.stdout"
  printf 'PASS %s forwarded Proc scopes\n' "$mode"
done
