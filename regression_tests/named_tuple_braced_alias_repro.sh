#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$ROOT/regression_tests/fixtures/named_tuple_braced_alias.cr"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-named-tuple-braces.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

sed 's/Metadata.named({key: 23/Metadata.named({wrong: 23/' "$SOURCE" > "$WORK/wrong_key.cr"
sed 's/Metadata.named({key: 23, value: /Metadata.named({23, /' "$SOURCE" > "$WORK/positional.cr"
sed 's/Metadata.named({key: 23/Metadata.named({key: true/' "$SOURCE" > "$WORK/wrong_field_type.cr"

for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    command=("$SAFE" "$CRYSTAL" 20 2048 build --prelude=empty --no-debug)
  else
    eager=0
    if [[ "$mode" == eager ]]; then eager=1; fi
    command=(env "ADAMAS_EAGER_HIR=$eager" "$SAFE" "$ADAMAS" 20 2048
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi

  output="$WORK/alias.$mode"
  if ! "${command[@]}" "$SOURCE" -o "$output" >"$output.compile.log" 2>&1; then
    cat "$output.compile.log" >&2
    exit 1
  fi
  if ! "$SAFE" "$output" 5 512 >"$output.run.log" 2>&1; then
    cat "$output.run.log" >&2
    exit 1
  fi
  printf 'PASS named and positional aliases (%s)\n' "$mode"

  for fixture in wrong_key positional wrong_field_type; do
    output="$WORK/$fixture.$mode"
    if "${command[@]}" "$WORK/$fixture.cr" -o "$output" >"$output.compile.log" 2>&1 ||
      ! grep -Eiq '(no overload matches Metadata.named|expected argument.*Metadata.named)' "$output.compile.log"; then
      cat "$output.compile.log" >&2
      exit 1
    fi
    printf 'PASS rejected %s (%s)\n' "$fixture" "$mode"
  done
done
