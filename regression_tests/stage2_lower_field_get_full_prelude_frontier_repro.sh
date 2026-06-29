#!/usr/bin/env bash
# Frontier guard: a produced s2 compiler must get past the old full-prelude
# lower_field_get SIGSEGV while compiling a minimal `puts "x"` program.
#
# This is not a full bootstrap-readiness test. The current accepted downstream
# frontier is a nilable Location? argument crash in Time::Format#initialize
# after the compiler has already passed the old lower_field_get crash and the
# old Time::Location.local undefined-extern stub.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_full_prelude_frontier.XXXXXX")"
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

if grep -Fq 'STUB CALLED: Time$CCLocation$Dlocal' "$LOG"; then
  echo "stage2_lower_field_get_full_prelude_frontier_failed: old Time::Location.local stub returned" >&2
  tail -120 "$LOG" >&2 || true
  exit 1
fi

if grep -Eq 'lower_field_get|hir_type_is_lib_struct' "$LOG"; then
  echo "stage2_lower_field_get_full_prelude_frontier_failed: old lower_field_get crash returned" >&2
  tail -120 "$LOG" >&2 || true
  exit 1
fi

if [[ $status -eq 0 && -x "$OUT" ]]; then
  echo "stage2_lower_field_get_full_prelude_frontier_ok status=0"
  exit 0
fi

if [[ $status -eq 139 ]] || grep -Eq 'Segmentation fault|EXC_BAD_ACCESS' "$LOG"; then
  LLDB_LOG="$TMP_DIR/lldb.log"
  set +e
  lldb --batch \
    -o "run $SRC -o $OUT.lldb" \
    -k 'bt 20' \
    -k 'quit' \
    "$COMPILER" >"$LLDB_LOG" 2>&1
  set -e

  if grep -Eq 'lower_field_get|hir_type_is_lib_struct' "$LLDB_LOG"; then
    echo "stage2_lower_field_get_full_prelude_frontier_failed: old lower_field_get crash returned" >&2
    tail -120 "$LLDB_LOG" >&2 || true
    exit 1
  fi

  if grep -Fq 'Time$CCFormat$Hinitialize$$String_Nil$_$OR$_Location' "$LLDB_LOG"; then
    echo "stage2_lower_field_get_full_prelude_frontier_ok frontier=time_format_nilable_location_param"
    exit 0
  fi

  echo "stage2_lower_field_get_full_prelude_frontier_failed: unclassified segfault status=$status" >&2
  tail -120 "$LOG" >&2 || true
  tail -80 "$LLDB_LOG" >&2 || true
  exit 1
fi

echo "stage2_lower_field_get_full_prelude_frontier_failed: unclassified status=$status" >&2
tail -120 "$LOG" >&2 || true
exit 1
