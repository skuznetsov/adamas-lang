#!/usr/bin/env bash
# Callback generic outputs use completed actual member results before body lowering.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export ADAMAS_ROOT="$ROOT_DIR"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
exec python3 "$ROOT_DIR/regression_tests/fixtures/callback_member_source_result/run.py" "$ADAMAS_BIN"
