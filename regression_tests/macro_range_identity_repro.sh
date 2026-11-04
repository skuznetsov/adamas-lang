#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURES="$ROOT/regression_tests/fixtures/macro_range_identity"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-macro-range-identity.XXXXXX")"
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

  for entry in string_bounds:ACE collection_bounds:AC require_argument:A iteration:ACEFG enum_conversion_name:A \
    invalid_bound:reject invalid_receiver:reject invalid_arity:reject invalid_method_arity:reject; do
    name="${entry%:*}"
    expected="${entry#*:}"
    source="$FIXTURES/$name.cr"
    output="$WORK/$mode.$name"
    log="$output.compile.log"
    status=0
    if [[ "$mode" == stock ]]; then
      "$SAFE" "$CRYSTAL" 120 8192 build "$source" --prelude=empty --no-debug \
        "${link_flags[@]}" -o "$output" >"$log" 2>&1 || status=$?
    else
      "$SAFE" "$ADAMAS" 120 8192 "$source" --no-prelude --no-debug --no-ast-cache \
        --no-llvm-cache -o "$output" >"$log" 2>&1 || status=$?
    fi
    if [[ "$expected" == reject ]]; then
      case "$name" in
        invalid_bound) diagnostic='range begin must be a NumberLiteral' ;;
        invalid_receiver) diagnostic="undefined macro method 'CharLiteral#[]'" ;;
        invalid_arity)
          diagnostic='macro range indexing expects one index'
          if [[ "$mode" == stock ]]; then
            diagnostic="wrong number of arguments for macro 'StringLiteral#[]'"
          fi
          ;;
        invalid_method_arity)
          diagnostic='RangeLiteral#begin expects no arguments'
          if [[ "$mode" == stock ]]; then
            diagnostic="wrong number of arguments for macro 'RangeLiteral#begin'"
          fi
          ;;
      esac
      if [[ "$status" != 1 ]] || ! grep -Fq "$diagnostic" "$log"; then
        cat "$log" >&2
        printf 'FAIL %s %s (compile exit %s)\n' "$mode" "$name" "$status" >&2
        exit 1
      fi
    else
      if [[ "$status" != 0 ]]; then
        cat "$log" >&2
        printf 'FAIL %s %s (compile exit %s)\n' "$mode" "$name" "$status" >&2
        exit 1
      fi
      RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 >"$output.stdout"
      printf '%s' "$expected" >"$output.expected"
      diff -u "$output.expected" "$output.stdout"
    fi
    printf 'PASS %s %s\n' "$mode" "$name"
  done
done
