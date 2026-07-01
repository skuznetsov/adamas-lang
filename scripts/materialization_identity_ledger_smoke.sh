#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/materialization-identity-ledger.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
LOG="$TMP_DIR/compile.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
class Box
  def initialize(@x : Int32)
  end

  def value
    @x
  end
end

box = Box.new(7)
puts box.value
CR

set +e
ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 1024 "$SRC" -o "$BIN" >"$LOG" 2>&1
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "FAIL: compiler exited with rc=$rc" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q '^\[MAT_ID\]' "$LOG"; then
  echo "FAIL: materialization identity ledger emitted no rows" >&2
  tail -120 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q '^\[MAT_TX\]' "$LOG"; then
  echo "FAIL: materialization transaction ledger emitted no rows" >&2
  tail -120 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q 'state_key=' "$LOG" || ! grep -q 'body_symbol=' "$LOG" || ! grep -q 'override_reason=' "$LOG"; then
  echo "FAIL: materialization identity rows are missing required fields" >&2
  grep '^\[MAT_ID\]' "$LOG" >&2 || true
  exit 1
fi

if ! grep -q 'identity_status=' "$LOG" || ! grep -q 'symbol_relation=' "$LOG" || ! grep -q 'required_contract=' "$LOG"; then
  echo "FAIL: materialization transaction rows are missing required fields" >&2
  grep '^\[MAT_TX\]' "$LOG" >&2 || true
  exit 1
fi

echo "PASS materialization_identity_ledger_smoke"
