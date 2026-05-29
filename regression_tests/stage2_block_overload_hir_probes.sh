#!/usr/bin/env bash
# Emits HIR and asserts block overload symbols: typed arity must win over arity-only
# when multiple block overloads exist; two positional args + block must not collapse
# to a one-arg block overload.
#
# The wrapper sets CRYSTAL_V2_STOP_AFTER_HIR=1 locally. Unset CRYSTAL_V2_STOP_AFTER_HIR
# in the parent shell when doing a full compile/link of other programs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT_DIR/regression_tests/stage2_block_overload_hir_probes.cr"
CC="${1:-"$ROOT_DIR/bin/adamas"}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_block_overload_hir_probes.XXXXXX")"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

if [[ ! -x "$CC" ]]; then
  echo "error: compiler not executable: $CC" >&2
  exit 2
fi

OUT="$WORKDIR/out"
WRAPPER="$WORKDIR/run.sh"
{
  echo "#!/usr/bin/env bash"
  echo "set -euo pipefail"
  echo "export CRYSTAL_V2_STOP_AFTER_HIR=1"
  printf 'exec %q ' "$CC"
  printf '%q ' --emit hir "$SRC" -o "$OUT"
  echo
} >"$WRAPPER"
chmod +x "$WRAPPER"

if ! "$ROOT_DIR/scripts/run_safe.sh" "$WRAPPER" 120 4096; then
  echo "error: HIR emission failed" >&2
  exit 1
fi

HIR="${OUT}.hir"
if [[ ! -f "$HIR" ]]; then
  echo "error: missing $HIR" >&2
  exit 1
fi

# Typed Int32 block overload must be used for m(1) { }, not the String overload.
if ! grep -q 'call.*BlockOverloadTypedProbe#m\$Int32_block' "$HIR"; then
  echo "error: expected Int32 block overload in HIR call for BlockOverloadTypedProbe#m(Int32)" >&2
  exit 1
fi

# Two positional args + block must resolve to the two-int block overload.
if ! grep -q 'call.*TwoArgBlockProbe#m\$Int32_Int32_block' "$HIR"; then
  echo "error: expected two-arg block overload in HIR call for TwoArgBlockProbe#m(Int32, Int32)" >&2
  exit 1
fi

echo "ok: stage2_block_overload_hir_probes"
