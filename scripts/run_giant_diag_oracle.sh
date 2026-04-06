#!/usr/bin/env bash
# Run crystal_v2 on macro dump carriers with CRYSTAL_V2_MACRO_BODY_GIANT_DIAG=1 and print
# only immediate giant JSON lines (stderr) — quick oracle without LLDB.
#
# Does not change compilation semantics (observability only).
#
# Usage (from repo root):
#   crystal build src/crystal_v2.cr -o bin/crystal_v2 --error-trace
#   scripts/run_giant_diag_oracle.sh [path/to/crystal_v2]
#
# Optional (exported before invoking this script):
#   CRYSTAL_V2_MACRO_BODY_GIANT_DIAG=1          # default: 1
#   CRYSTAL_V2_MACRO_BODY_GIANT_SINGLE_BYTES
#   CRYSTAL_V2_MACRO_BODY_GIANT_CUMULATIVE_BYTES
#
# For long compiles, wrap the compiler with scripts/run_safe.sh if needed.
#
# Bootstrap spot-check (optional, slow): same env, then
#   CRYSTAL_V2_MACRO_BODY_GIANT_DIAG=1 bin/crystal_v2 src/crystal_v2.cr -o /tmp/cv2_boot.out
# and look for macro_body_giant on stderr — expect primitives giant on the prelude path.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${1:-$REPO_ROOT/bin/crystal_v2}"
STAGING="${TMPDIR:-/tmp}/crystal_v2_giant_oracle_$$"
mkdir -p "$STAGING"
trap 'rm -rf "$STAGING"' EXIT

export CRYSTAL_V2_MACRO_BODY_GIANT_DIAG="${CRYSTAL_V2_MACRO_BODY_GIANT_DIAG:-1}"

if [[ ! -x "$COMPILER" ]]; then
  echo "error: not an executable compiler: $COMPILER" >&2
  exit 1
fi

CARRIERS=(
  "scripts/macro_dump_stdlib_heavy_carrier.cr"
  "scripts/macro_dump_heavy_carrier.cr"
  "scripts/macro_dump_flag_carrier.cr"
)

echo "=== GIANT_DIAG oracle ==="
echo "compiler=$COMPILER"
echo "CRYSTAL_V2_MACRO_BODY_GIANT_DIAG=$CRYSTAL_V2_MACRO_BODY_GIANT_DIAG"
echo ""

any_giant=0
any_fail=0
for rel in "${CARRIERS[@]}"; do
  src="$REPO_ROOT/$rel"
  base="$(basename "$rel" .cr)"
  err="$STAGING/${base}.stderr"
  out="$STAGING/${base}.bin"
  echo "--- $rel ---"
  if ! "$COMPILER" "$src" -o "$out" 2>"$err"; then
    echo "[compile failed] (last 30 lines of stderr:)"
    tail -30 "$err" >&2 || true
    any_fail=1
    continue
  fi
  if rg -q 'macro_body_giant' "$err" 2>/dev/null; then
    rg 'macro_body_giant' "$err" || true
    any_giant=1
  else
    echo "(no macro_body_giant lines on stderr)"
  fi
  echo ""
done

if [[ "$any_fail" -ne 0 ]]; then
  exit 1
fi
if [[ "$any_giant" -eq 0 ]]; then
  echo "note: no giant hits across carriers (thresholds may be too high for these inputs)."
fi
exit 0
