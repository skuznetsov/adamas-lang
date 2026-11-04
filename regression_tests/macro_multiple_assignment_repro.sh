#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURES="$ROOT/regression_tests/fixtures/macro_multiple_assignment"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-macro-multi-assign.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
link_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  link_flags+=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

for mode in stock lazy eager; do
  unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
  if [[ "$mode" == eager ]]; then
    export ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1
  fi

  for entry in annotation_arg_destructuring:ABCDEF literal:BACDEFGHIJKLMNOQSTU \
    reject_comma_arity:reject reject_duplicate_rest:reject reject_middle_rest_arity:reject reject_strict_arity:reject \
    reject_multi_index_bounds:reject reject_single_index_type:reject; do
    name="${entry%:*}"
    expected="${entry#*:}"
    source="$FIXTURES/$name.cr"
    output="$WORK/$mode.$name"
    log="$output.compile.log"
    status=0
    flags=()
    if [[ "$name" == reject_strict_arity ]]; then
      flags+=(-Dstrict_multi_assign)
    fi

    if [[ "$mode" == stock ]]; then
      "$SAFE" "$CRYSTAL" 120 8192 build "$source" --prelude=empty --no-debug \
        "${flags[@]}" "${link_flags[@]}" -o "$output" >"$log" 2>&1 || status=$?
    else
      "$SAFE" "$ADAMAS" 120 8192 "$source" --no-prelude --no-debug --no-ast-cache \
        --no-llvm-cache "${flags[@]}" -o "$output" >"$log" 2>&1 || status=$?
    fi

    if [[ "$expected" == reject ]]; then
      diagnostic='Multiple assignment count mismatch'
      if [[ "$name" == reject_duplicate_rest ]]; then
        diagnostic='splat assignment already specified'
      elif [[ "$name" == reject_multi_index_bounds ]]; then
        diagnostic='index out of bounds'
      elif [[ "$name" == reject_single_index_type ]]; then
        diagnostic='expected index argument to ArrayLiteral#[]= to be a number'
      elif [[ "$mode" == stock && "$name" != reject_comma_arity ]]; then
        # The empty prelude has no IndexError for Crystal's macro arity check.
        diagnostic='undefined constant ::IndexError'
      fi
      if [[ "$status" != 1 ]] || ! grep -Fq "$diagnostic" "$log"; then
        cat "$log" >&2
        printf 'FAIL %s %s (compile exit %s)\n' "$mode" "$name" "$status" >&2
        exit 1
      fi
    else
      if [[ "$status" != 0 ]]; then
        cat "$log" >&2
        exit 1
      fi
      RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 >"$output.stdout"
      printf '%s\n' "$expected" >"$output.expected"
      diff -u "$output.expected" "$output.stdout"
    fi
    printf 'PASS %s %s\n' "$mode" "$name"
  done
done
