#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="${ADAMAS_ROOT_DIR:-${ADAMAS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}}"
if [[ ! -x "$ROOT_DIR/scripts/run_safe.sh" ]]; then
  echo "set ADAMAS_ROOT_DIR to the Adamas checkout containing scripts/run_safe.sh" >&2
  exit 2
fi

exec python3 "$SCRIPT_DIR/callback_replay_contract_runner.py" "$ROOT_DIR" "$@"
