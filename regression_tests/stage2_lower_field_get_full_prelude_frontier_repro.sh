#!/usr/bin/env bash
# Frontier guard: a produced s2 compiler must get past the old full-prelude
# lower_field_get SIGSEGV while compiling a minimal `puts "x"` program.
#
# This is not a full bootstrap-readiness test. The current accepted downstream
# frontier is an undefined-extern abort stub for Time::Location.local; the guard
# fails only if the old lower_field_get crash or another unclassified crash
# returns.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_lower_field_get_frontier.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/puts_x.cr"
OUT="$TMP_DIR/puts_x"
LOG="$TMP_DIR/compile.log"

cat > "$SRC" <<'CR'
puts "x"
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 2048 "$SRC" -o "$OUT" >"$LOG" 2>&1
status=$?
set -e

if [[ $status -eq 139 ]] || grep -Eq 'Segmentation fault|EXC_BAD_ACCESS|lower_field_get' "$LOG"; then
  echo "stage2_lower_field_get_full_prelude_frontier_failed: old lower_field_get crash returned" >&2
  tail -120 "$LOG" >&2 || true
  exit 1
fi

if [[ $status -eq 0 && -x "$OUT" ]]; then
  echo "stage2_lower_field_get_full_prelude_frontier_ok status=0"
  exit 0
fi

if grep -Fq 'STUB CALLED: Time$CCLocation$Dlocal' "$LOG"; then
  echo "stage2_lower_field_get_full_prelude_frontier_ok frontier=time_location_local_stub"
  exit 0
fi

echo "stage2_lower_field_get_full_prelude_frontier_failed: unclassified status=$status" >&2
tail -120 "$LOG" >&2 || true
exit 1
