#!/usr/bin/env bash
# Preserve exact Int128/UInt128 literals through parsing, HIR, MIR, and LLVM.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-crystal}"
if [[ "$ORIGINAL_HINT" == */* ]]; then
  ORIGINAL="$ORIGINAL_HINT"
else
  ORIGINAL="$(command -v "$ORIGINAL_HINT" || true)"
fi
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/wide_integer_literals"
for executable in "$COMPILER" "$ORIGINAL" "$SAFE_RUN"; do
  if [[ -z "$executable" || ! -x "$executable" ]]; then
    echo "ERROR: executable not found: $executable" >&2
    exit 2
  fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wide-integer-literals.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == 1 ]]; then
    echo "kept_tmp=$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

compile_literal() {
  local stage="$1" fixture="$2" output="$3" log="$4"
  local link_args=()
  if [[ "$stage" == original ]]; then
    if [[ "$(uname -s)" == Darwin ]]; then
      link_args=(--link-flags=-fuse-ld=/usr/bin/ld)
    fi
    CRYSTAL_CACHE_DIR="$WORK_DIR/cache.original" "$SAFE_RUN" "$ORIGINAL" 60 4096 \
      build --prelude=empty --no-debug "${link_args[@]}" "$FIXTURES/$fixture.cr" \
      -o "$output" >"$log" 2>&1
  else
    ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$COMPILER" 60 4096 \
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache "$FIXTURES/$fixture.cr" \
      -o "$output" >"$log" 2>&1
  fi
}

# Qualify all sources with stock Crystal before running the candidate.
for stage in original candidate; do
  output="$WORK_DIR/$stage.retention"
  log="$WORK_DIR/$stage.retention.compile.log"
  if ! compile_literal "$stage" retention "$output" "$log"; then
    echo "FAIL[$stage]: valid wide integer literal was rejected" >&2
    cat "$log" >&2
    exit 1
  fi
  if ! "$SAFE_RUN" "$output" 5 512 >"$WORK_DIR/$stage.retention.run.log" 2>&1; then
    echo "FAIL[$stage]: wide integer literal value changed" >&2
    cat "$WORK_DIR/$stage.retention.run.log" >&2
    exit 1
  fi

  for fixture in overflow_i128 overflow_u128 malformed_u128; do
    output="$WORK_DIR/$stage.$fixture"
    log="$WORK_DIR/$stage.$fixture.log"
    if compile_literal "$stage" "$fixture" "$output" "$log"; then
      echo "FAIL[$stage]: invalid wide integer literal was accepted: $fixture" >&2
      exit 1
    fi
    if [[ -e "$output" ]]; then
      echo "FAIL[$stage]: invalid literal produced an executable: $fixture" >&2
      exit 1
    fi
    if ! grep -Eiq 'Int128|UInt128|integer literal|number|digits|fit' "$log"; then
      echo "FAIL[$stage]: missing wide integer diagnostic: $fixture" >&2
      cat "$log" >&2
      exit 1
    fi
  done
done

echo "PASS: 128-bit literals retain exact values and invalid values fail closed"
