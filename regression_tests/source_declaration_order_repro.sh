#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -z "${ADAMAS_REPO_ROOT:-}" ]; then
  ADAMAS_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -z "$ADAMAS_REPO_ROOT" ]; then
    echo "Set ADAMAS_REPO_ROOT to the Adamas checkout" >&2
    exit 2
  fi
  export ADAMAS_REPO_ROOT
fi
export ADAMAS_SOURCE_DECLARATION_FIXTURES="$SCRIPT_DIR/source_declaration_order"
if [ -z "${ADAMAS_RUN_SAFE:-}" ]; then
  export ADAMAS_RUN_SAFE="$ADAMAS_REPO_ROOT/scripts/run_safe.sh"
fi
exec python3 "$SCRIPT_DIR/source_declaration_order_repro.py" "$@"
