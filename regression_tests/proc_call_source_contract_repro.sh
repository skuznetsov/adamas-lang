#!/usr/bin/env bash
# Original-first concrete Proc input contract; native runs use run_safe.sh.
set -euo pipefail
if [[ $# -gt 1 ]]; then
  echo "usage: $0 [adamas-compiler]" >&2
  exit 2
fi
ROOT_DIR="${ADAMAS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
exec python3 "$(dirname "${BASH_SOURCE[0]}")/proc_call_source_contract/run.py" "$COMPILER"
