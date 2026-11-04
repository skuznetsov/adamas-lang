#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$ROOT/regression_tests/fixtures/rooted_value_join"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-rooted-value-join.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

# The same value cannot satisfy the shadow type's restriction.
sed 's/def root_code(error : ::EndpointError)/def root_code(error : ::Platform::EndpointError)/' \
  "$SOURCE/lexical_shadow.cr" > "$WORK/wrong_shadow.cr"

for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    command=("$SAFE" "$CRYSTAL" 20 2048 build --prelude=empty --no-debug)
  else
    eager=0
    if [[ "$mode" == eager ]]; then eager=1; fi
    command=(env "ADAMAS_EAGER_HIR=$eager" "$SAFE" "$ADAMAS" 20 2048
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi

  for fixture in lexical_shadow included_qualified; do
    output="$WORK/$fixture.$mode"
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

  output="$WORK/wrong_shadow.$mode"
  if "${command[@]}" "$WORK/wrong_shadow.cr" -o "$output" >"$output.compile.log" 2>&1 ||
    ! grep -Eiq '(no overload matches root_code.*\(EndpointError\)|expected argument.*root_code.*Platform::EndpointError.*EndpointError)' "$output.compile.log"; then
    cat "$output.compile.log" >&2
    exit 1
  fi
  printf 'PASS wrong_shadow (%s)\n' "$mode"
done
