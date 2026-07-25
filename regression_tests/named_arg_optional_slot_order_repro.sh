#!/usr/bin/env bash
# Named arguments must bind by name, not by source/declaration position.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SOURCE="$ROOT_DIR/regression_tests/named_arg_optional_slot_order_repro.cr"
TMP_DIR="$(mktemp -d /tmp/adamas_named_arg_slots.XXXXXX)"
OUT="$TMP_DIR/named_arg_slots"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 \
  "$SOURCE" --no-prelude -o "$OUT"
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512

echo "named_arg_optional_slot_order_repro_ok"
