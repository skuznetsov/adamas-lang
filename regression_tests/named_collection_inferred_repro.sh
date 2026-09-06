#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_named_collection_inferred.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found or not executable: $COMPILER" >&2
  exit 2
fi

run_positive() {
  local name="$1"
  local source="$2"
  shift 2
  local binary="$WORK_DIR/$name"
  local compile_log="$WORK_DIR/$name.compile.log"
  local runtime_log="$WORK_DIR/$name.runtime.log"

  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
    "$ROOT_DIR/regression_tests/$source" "$@" -o "$binary" >"$compile_log" 2>&1; then
    cat "$compile_log" >&2
    echo "FAIL[$name]: compiler failed" >&2
    exit 1
  fi

  if ! "$ROOT_DIR/scripts/run_safe.sh" "$binary" 5 512 >"$runtime_log" 2>&1; then
    cat "$runtime_log" >&2
    echo "FAIL[$name]: generated program failed" >&2
    exit 1
  fi
}

run_positive inferred named_collection_inferred_repro.cr --no-prelude
run_positive set_no_prelude named_collection_set_repro.cr --no-prelude
run_positive set_stdlib named_collection_stdlib_set_repro.cr
run_positive explicit_empty named_collection_empty_explicit.cr --no-prelude

empty_log="$WORK_DIR/empty_inferred.compile.log"
set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
  "$ROOT_DIR/regression_tests/named_collection_empty_inferred.cr" --no-prelude \
  -o "$WORK_DIR/empty_inferred" >"$empty_log" 2>&1
empty_status=$?
set -e
if [[ "$empty_status" -eq 0 ]]; then
  echo "FAIL[empty_inferred]: bare generic empty literal unexpectedly compiled" >&2
  cat "$empty_log" >&2
  exit 1
fi
if ! rg -Fq "cannot infer generic type arguments for an empty named collection literal" "$empty_log"; then
  echo "FAIL[empty_inferred]: rejection did not use the bounded diagnostic" >&2
  cat "$empty_log" >&2
  exit 1
fi

echo "PASS: inferred named collections preserve element typing, enum and absolute receivers, evaluation order, stdlib Set storage, explicit empty construction, and fail-closed empty inference"
