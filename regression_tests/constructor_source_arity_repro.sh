#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export ADAMAS_ROOT="${ADAMAS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
export ADAMAS_RUN_SAFE="${ADAMAS_RUN_SAFE:-$ADAMAS_ROOT/scripts/run_safe.sh}"
python3 "$SCRIPT_DIR/constructor_source_arity/run_original_first.py" "$@"
exec python3 "$SCRIPT_DIR/constructor_source_arity/c_layout_controls/run_original_first.py" "$@"
