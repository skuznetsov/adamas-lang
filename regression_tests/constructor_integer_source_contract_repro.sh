#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="${ADAMAS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
export ADAMAS_ROOT="$ROOT"
if [[ "$#" -eq 0 ]]; then
  set -- "${ADAMAS_BIN:-$ROOT/bin/adamas}"
fi
exec python3 -B "$SCRIPT_DIR/constructor_integer_source_contract/run_original_first.py" "$@"
