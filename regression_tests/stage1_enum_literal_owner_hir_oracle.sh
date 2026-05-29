#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SRC="$ROOT_DIR/regression_tests/stage1_enum_literal_owner_hir_oracle.cr"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage1_enum_literal_owner.XXXXXX")"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

WRAPPER="$WORKDIR/run.sh"
LOG="$WORKDIR/run.log"
ARTIFACT="$WORKDIR/out.hir"

{
  echo "#!/usr/bin/env bash"
  echo "set -euo pipefail"
  echo "export ADAMAS_STOP_AFTER_HIR=1"
  printf 'exec %q ' "$COMPILER"
  printf '%q ' --release --no-prelude --no-ast-cache --emit hir
  printf '%q ' "$SRC" -o "$WORKDIR/out"
  echo
} >"$WRAPPER"
chmod +x "$WRAPPER"

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$WRAPPER" 40 2048 >"$LOG" 2>&1
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  echo "reproduced: compiler failed before HIR on enum literal owner oracle"
  tail -n 80 "$LOG"
  exit 1
fi

if [[ ! -f "$ARTIFACT" ]]; then
  echo "inconclusive: expected artifact missing: $ARTIFACT" >&2
  tail -n 80 "$LOG" >&2 || true
  exit 2
fi

INT32_COUNT="$(grep -c 'Int32#primitive?()' "$ARTIFACT" || true)"
KIND_COUNT="$(grep -c 'Kind#primitive?()' "$ARTIFACT" || true)"

if [[ "$INT32_COUNT" != "1" || "$KIND_COUNT" != "1" ]]; then
  echo "reproduced: enum literal owner drifted during HIR lowering"
  echo "expected exactly one Int32#primitive?() and one Kind#primitive?() call"
  echo "observed Int32=$INT32_COUNT Kind=$KIND_COUNT"
  rg -n 'Int32#primitive\\?|Kind#primitive\\?|call .*primitive' "$ARTIFACT" -n -S || true
  exit 1
fi

echo "not reproduced: enum literal owner is preserved in HIR lowering"
