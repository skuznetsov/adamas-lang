#!/usr/bin/env bash
# Guard that responds_to?(:object_id) follows Crystal's Reference-only
# semantics and is not polluted by synthetic lowered function entries.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_object_id_responds_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/object_id_responds.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/run_safe.log"
VALUE_HIR="$TMP_DIR/value_probe.hir"
REF_HIR="$TMP_DIR/ref_probe.hir"

cat >"$SRC" <<'CR'
def value_probe(x : UInt32)
  if x.responds_to?(:object_id)
    x.object_id
  else
    1_u64
  end
end

def ref_probe(x : String)
  if x.responds_to?(:object_id)
    x.object_id
  else
    2_u64
  end
end

value_probe(1_u32)
ref_probe("x")
CR

CRYSTAL_V2_STOP_AFTER_HIR=1 \
CRYSTAL_V2_PHASE_STATS=1 \
DEBUG_MISSING_SUMMARY=1 \
DEBUG_MISSING_SAMPLES=1 \
DEBUG_MISSING_TOP=20 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 \
    "$SRC" --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

awk '/^func @value_probe/ {capture=1} capture {print} capture && /^}/ {exit}' "$OUT.hir" >"$VALUE_HIR"
awk '/^func @ref_probe/ {capture=1} capture {print} capture && /^}/ {exit}' "$OUT.hir" >"$REF_HIR"

if grep -q 'UInt32#object_id' "$VALUE_HIR" "$LOG"; then
  echo "p2 object_id responds_to regression: UInt32 object_id was emitted" >&2
  grep -n 'UInt32#object_id' "$VALUE_HIR" "$LOG" >&2 || true
  exit 1
fi

if ! grep -q 'literal false : Bool' "$VALUE_HIR"; then
  echo "p2 object_id responds_to regression: UInt32 responds_to? did not lower to false" >&2
  cat "$VALUE_HIR" >&2
  exit 1
fi

if ! grep -q 'Reference#object_id' "$REF_HIR"; then
  echo "p2 object_id responds_to regression: String object_id path was not preserved" >&2
  cat "$REF_HIR" >&2
  exit 1
fi

echo "p2_object_id_responds_to_semantics_ok"
