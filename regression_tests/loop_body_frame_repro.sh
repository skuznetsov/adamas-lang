#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-$ROOT/bin/adamas}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-loop-body-frame.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

for form in loop while until; do
  case "$form" in
    loop) header="loop do" ;;
    while) header="while true" ;;
    until) header="until false" ;;
  esac
  for kind in valid invalid; do
    argument=0
    if [[ "$kind" == invalid ]]; then argument=false; fi
    sed -e "s/LOOP_HEADER/$header/" -e "s/CALL_ARGUMENT/$argument/" \
      "$ROOT/regression_tests/fixtures/loop_body_frame.cr" >"$WORK/$form.$kind.cr"
  done
done

compile() {
  local compiler="$1" source="$2" output="$3"
  if [[ "$compiler" == stock ]]; then
    "$SAFE" "$CRYSTAL" 20 2048 build --prelude=empty --no-debug "$source" -o "$output"
  else
    local eager=0
    if [[ "$compiler" == eager ]]; then eager=1; fi
    ADAMAS_EAGER_HIR="$eager" "$SAFE" "$ADAMAS" 20 2048 \
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache "$source" -o "$output"
  fi
}

for compiler in stock lazy eager; do
  for form in loop while until; do
    output="$WORK/$compiler.$form"
    if ! compile "$compiler" "$WORK/$form.valid.cr" "$output" >"$output.compile.log" 2>&1; then
      cat "$output.compile.log" >&2
      exit 1
    fi
    if ! "$SAFE" "$output" 5 512 >"$output.run.log" 2>&1; then
      cat "$output.run.log" >&2
      exit 1
    fi

    # A rejected call must retain its type diagnostic after unwinding the loop.
    rc=0
    compile "$compiler" "$WORK/$form.invalid.cr" "$output.invalid" >"$output.invalid.log" 2>&1 || rc=$?
    if [[ "$rc" != 1 ]] ||
       ! grep -Eq 'IntConsumer#consume.*Int32, not Bool|incompatible explicit arguments for concrete generic receiver IntConsumer#consume' "$output.invalid.log" ||
       grep -q 'lost its owned' "$output.invalid.log"; then
      cat "$output.invalid.log" >&2
      exit 1
    fi
    printf 'PASS loop body frame (%s, %s)\n' "$compiler" "$form"
  done
done
