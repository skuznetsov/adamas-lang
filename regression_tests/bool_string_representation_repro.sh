#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export ADAMAS_ROOT="${ADAMAS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
export ADAMAS_RUN_SAFE="${ADAMAS_RUN_SAFE:-$ADAMAS_ROOT/scripts/run_safe.sh}"
exec python3 "$SCRIPT_DIR/bool_string_representation/run_original_first.py" "$@"
