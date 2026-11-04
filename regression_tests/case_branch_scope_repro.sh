#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-$ROOT/bin/adamas}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-case-branch-scope.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

FIXTURE="$ROOT/regression_tests/fixtures/case_branch_scope.cr"
sed -e 's/WHEN_ARG/0/' -e 's/ELSE_ARG/1/' "$FIXTURE" >"$WORK/valid.cr"
sed -e 's/WHEN_ARG/false/' -e 's/ELSE_ARG/1/' "$FIXTURE" >"$WORK/invalid_when.cr"
sed -e 's/WHEN_ARG/0/' -e 's/ELSE_ARG/false/' "$FIXTURE" >"$WORK/invalid_else.cr"

compile() {
  local mode="$1" source="$2" output="$3"
  if [[ "$mode" == stock ]]; then
    "$SAFE" "$CRYSTAL" 20 2048 build --prelude=empty --no-debug "$source" -o "$output"
  else
    local eager=0
    if [[ "$mode" == eager ]]; then eager=1; fi
    ADAMAS_EAGER_HIR="$eager" "$SAFE" "$ADAMAS" 20 2048 \
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache "$source" -o "$output"
  fi
}

for mode in stock lazy eager; do
  if ! compile "$mode" "$WORK/valid.cr" "$WORK/$mode" >"$WORK/compile.log" 2>&1; then
    cat "$WORK/compile.log" >&2
    exit 1
  fi
  if ! "$SAFE" "$WORK/$mode" 5 512 >"$WORK/run.log" 2>&1; then
    cat "$WORK/run.log" >&2
    exit 1
  fi

  for branch in when else; do
    rc=0
    compile "$mode" "$WORK/invalid_$branch.cr" "$WORK/$mode.invalid" >"$WORK/invalid.log" 2>&1 || rc=$?
    if [[ "$rc" != 1 ]] ||
       ! grep -Eq 'IntConsumer#consume.*Int32, not Bool|incompatible explicit arguments for concrete generic receiver IntConsumer#consume' "$WORK/invalid.log" ||
       grep -q 'lost its owned' "$WORK/invalid.log"; then
      cat "$WORK/invalid.log" >&2
      exit 1
    fi
    printf 'PASS case branch scope (%s, %s)\n' "$mode" "$branch"
  done
done
