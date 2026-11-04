#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$ROOT/regression_tests/fixtures/selected_call_family_body"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-selected-call-family.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

for fixture in unselected_typed_splat real_splat_and_defaults; do
  for mode in stock lazy eager; do
    output="$WORK/$fixture.$mode"
    if [[ "$mode" == stock ]]; then
      command=("$SAFE" "$CRYSTAL" 20 2048 build --prelude=empty --no-debug)
    else
      eager=0
      if [[ "$mode" == eager ]]; then eager=1; fi
      command=(env "ADAMAS_EAGER_HIR=$eager" "$SAFE" "$ADAMAS" 20 2048
        --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
    fi
    if ! "${command[@]}" "$SOURCE/$fixture.cr" -o "$output" >"$output.compile.log" 2>&1; then
      cat "$output.compile.log" >&2
      exit 1
    fi
    if ! "$SAFE" "$output" 5 512 >"$output.run.log" 2>&1; then
      cat "$output.run.log" >&2
      exit 1
    fi
    printf 'PASS %s (%s)\n' "$fixture" "$mode"
  done
done
