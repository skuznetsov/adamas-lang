#!/usr/bin/env bash
# Rooted and lexical callback result restrictions preserve class identity.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export ADAMAS_ROOT="$ROOT_DIR"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
exec python3 "$ROOT_DIR/regression_tests/fixtures/rooted_block_result/run.py" "$ADAMAS_BIN"
