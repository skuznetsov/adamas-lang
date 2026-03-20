#!/bin/bash
# Reproduces: type alias union dispatch in blocks reads tagged union layout
# instead of all-ref (ptr) layout, causing corrupted dispatch.
set -euo pipefail
COMPILER="${1:?Usage: $0 <compiler>}"
TMPBIN=$(mktemp /tmp/union_alias_dispatch_XXXXXX)
trap "rm -f $TMPBIN" EXIT
"$COMPILER" regression_tests/stage2_union_alias_block_dispatch_repro.cr --no-prelude -o "$TMPBIN" 2>/dev/null
OUTPUT=$(scripts/run_safe.sh "$TMPBIN" 5 512 2>/dev/null)
if echo "$OUTPUT" | grep -q "EXIT: 0"; then
  echo "not reproduced: union alias block dispatch works correctly"
  exit 0
else
  echo "reproduced: union alias block dispatch fails"
  exit 1
fi
