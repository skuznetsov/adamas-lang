#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-$ROOT/bin/adamas}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-initializer-lexical-self.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
export CRYSTAL_CACHE_DIR="$WORK/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

SOURCE="$ROOT/regression_tests/fixtures/initializer_lexical_self.cr"
for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    command=("$CRYSTAL" 20 2048 build --prelude=empty)
  else
    eager=0
    if [[ "$mode" == eager ]]; then eager=1; fi
    export ADAMAS_EAGER_HIR="$eager"
    command=("$ADAMAS" 20 2048 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  if ! "$SAFE" "${command[@]}" --no-debug "$SOURCE" -o "$WORK/$mode" >"$WORK/compile.log" 2>&1; then
    cat "$WORK/compile.log" >&2
    exit 1
  fi
  if ! "$SAFE" "$WORK/$mode" 5 512 >"$WORK/run.log" 2>&1; then
    cat "$WORK/run.log" >&2
    exit 1
  fi
  printf 'PASS initializer lexical self (%s)\n' "$mode"
done
