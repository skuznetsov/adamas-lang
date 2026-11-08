#!/usr/bin/env bash
# Bare nilary self syntax shares ordinary source-result selection and replay.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export ADAMAS_ROOT="${ADAMAS_ROOT:-$ROOT_DIR}"
exec python3 "$ROOT_DIR/regression_tests/fixtures/bare_self_source_result/run.py" "$@"
