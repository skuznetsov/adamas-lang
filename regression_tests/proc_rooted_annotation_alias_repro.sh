#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if (( $# > 1 )); then
  echo "usage: $0 [adamas-compiler]" >&2
  exit 2
fi
export ADAMAS_ROOT="${ADAMAS_ROOT:-$ROOT}"
exec python3 "$ROOT/regression_tests/proc_rooted_annotation_alias/run.py" "${1:-${ADAMAS_BIN:-$ROOT/bin/adamas}}"
