#!/usr/bin/env bash
# Late nested return types must retain their declaration owner.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="${RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
FIXTURE="$ROOT_DIR/regression_tests/late_nested_return_namespace_repro.cr"
TMP_DIR="$(mktemp -d /tmp/late_nested_return_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
for annotation in 'Info?' 'File::Info?' '::File::Info?'; do
  SRC="$TMP_DIR/probe.cr"
  OUT="$TMP_DIR/probe"
  sed "s/: Info?/: $annotation/" "$FIXTURE" > "$SRC"
  "$RUN_SAFE" "$COMPILER" 30 2048 "$SRC" --no-prelude -o "$OUT" > "$TMP_DIR/compile.log" 2>&1 || { cat "$TMP_DIR/compile.log"; exit 1; }
  "$RUN_SAFE" "$OUT" 5 512 > "$TMP_DIR/run.log" 2>&1 || { cat "$TMP_DIR/run.log"; exit 1; }
done
echo "late_nested_return_namespace_ok"
