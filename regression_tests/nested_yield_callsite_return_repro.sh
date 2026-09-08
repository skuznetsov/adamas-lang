#!/usr/bin/env bash
# A nested unannotated reader must forward Entry, not an ambient Pointer local.
# Exercise raw callbacks as well as inline yields; assert the emitted values.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="${RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
TMP_DIR="$(mktemp -d /tmp/nested_yield_callsite_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

for mode in inline raw; do
  OUT="$TMP_DIR/$mode"
  if [[ "$mode" == raw ]]; then
    ADAMAS_DISABLE_INLINE_YIELD=1 "$RUN_SAFE" "$COMPILER" 60 2048 \
      "$ROOT_DIR/regression_tests/nested_yield_callsite_return_repro.cr" \
      --no-prelude -o "$OUT" >"$OUT.compile.log" 2>&1 || { cat "$OUT.compile.log"; exit 1; }
  else
    env -u ADAMAS_DISABLE_INLINE_YIELD "$RUN_SAFE" "$COMPILER" 60 2048 \
      "$ROOT_DIR/regression_tests/nested_yield_callsite_return_repro.cr" \
      --no-prelude -o "$OUT" >"$OUT.compile.log" 2>&1 || { cat "$OUT.compile.log"; exit 1; }
  fi
  "$RUN_SAFE" "$OUT" 5 512 >"$OUT.run.log" 2>&1 || { cat "$OUT.run.log"; exit 1; }
  if ! grep -Fxq 'I^' "$OUT.run.log"; then
    echo "nested_yield_callsite_return_failed: $mode callback values differ" >&2
    cat "$OUT.run.log" >&2
    exit 1
  fi
done
echo "nested_yield_callsite_return_ok"
