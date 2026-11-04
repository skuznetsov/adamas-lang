#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-$ROOT/bin/adamas}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
FIXTURES="$ROOT/regression_tests/fixtures/class_argument_kind"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-class-argument-kind.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
export CRYSTAL_CACHE_DIR="$WORK/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    command=("$CRYSTAL" 20 2048 build --prelude=empty)
  else
    eager=0
    if [[ "$mode" == eager ]]; then eager=1; fi
    export ADAMAS_EAGER_HIR="$eager"
    command=("$ADAMAS" 20 2048 --no-prelude --no-ast-cache --no-llvm-cache)
  fi

  for source in "$FIXTURES"/*.cr; do
    fixture="$(basename "$source" .cr)"
    status=0
    "$SAFE" "${command[@]}" --no-debug "$source" -o "$WORK/repro" >"$WORK/compile.log" 2>&1 || status=$?
    if [[ "$fixture" == invalid_* ]]; then
      if [[ "$status" != 1 ]] ||
         ! grep -Eq "^(Error: expected argument .*'[^']*take'|error: no overload matches .*take)" "$WORK/compile.log"; then
        cat "$WORK/compile.log" >&2
        printf 'Expected overload rejection for %s (%s)\n' "$fixture" "$mode" >&2
        exit 1
      fi
    elif [[ "$status" != 0 ]]; then
      cat "$WORK/compile.log" >&2
      exit 1
    elif ! "$SAFE" "$WORK/repro" 5 512 >"$WORK/run.log" 2>&1; then
      cat "$WORK/run.log" >&2
      printf 'Unexpected result for %s (%s)\n' "$fixture" "$mode" >&2
      exit 1
    fi
    printf 'PASS class argument kind %s (%s)\n' "$fixture" "$mode"
  done
done
