#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$root/regression_tests/proc_source_contract/run.py" "${1:-$root/bin/adamas}"
