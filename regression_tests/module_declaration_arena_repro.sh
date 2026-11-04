#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURES="$ROOT/regression_tests/fixtures/module_declaration_arena"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-module-declaration-arena.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
if [[ "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
for mode in stock lazy; do
  for name in declared_errors unrelated_error; do
    source="$FIXTURES/$name.cr"
    output="$WORK/$mode.$name"
    log="$output.compile.log"
    status=0
    if [[ "$mode" == stock ]]; then
      "$SAFE" "$CRYSTAL" 120 8192 build "$source" --no-debug -o "$output" >"$log" 2>&1 || status=$?
    else
      "$SAFE" "$ADAMAS" 120 8192 "$source" --no-debug --no-ast-cache \
        --no-llvm-cache -o "$output" >"$log" 2>&1 || status=$?
    fi

    if [[ "$name" == unrelated_error ]]; then
      if [[ "$status" != 1 ]] ||
        ! grep -Eq "no overload matches|expected argument #1 to 'exception_kind'" "$log" ||
        ! grep -Fq 'ArenaRepro::Nested::Unrelated' "$log"; then
        cat "$log" >&2
        exit 1
      fi
    else
      if [[ "$status" != 0 ]]; then
        cat "$log" >&2
        exit 1
      fi
      RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 >"$output.stdout"
      printf AA >"$output.expected"
      diff -u "$output.expected" "$output.stdout"
    fi
    printf 'PASS %s %s\n' "$mode" "$name"
  done
done
