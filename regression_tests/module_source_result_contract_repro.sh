#!/usr/bin/env bash
# Exact module/forall result source contracts; original-first safe native checks.
set -euo pipefail
if [[ $# -gt 1 ]]; then
  echo "usage: $0 [adamas-compiler | --self-test | --original-only]" >&2
  exit 2
fi
ROOT_DIR="${ADAMAS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
exec python3 "$(dirname "${BASH_SOURCE[0]}")/fixtures/module_source_result_contract/run.py" "$COMPILER"
