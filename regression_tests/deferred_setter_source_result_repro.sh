#!/usr/bin/env bash
# Source-body results from property setters must survive caller narrowing/replay.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export ADAMAS_ROOT="${ADAMAS_ROOT:-$ROOT_DIR}"
exec python3 "$ROOT_DIR/regression_tests/fixtures/deferred_setter_source_result/run.py" "$@"
