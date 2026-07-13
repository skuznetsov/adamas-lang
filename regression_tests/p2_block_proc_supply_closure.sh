#!/usr/bin/env bash
set -euo pipefail

COMPILER="${1:-bin/adamas}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/adamas_block_proc_supply.XXXXXX)"
OUT="$TMP_DIR/block_proc_supply"
HIR="$OUT.hir"
LOG="$TMP_DIR/compile.log"

cleanup() {
  if [[ "${KEEP_TMP:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "[p2_block_proc_supply_closure] kept tmp: $TMP_DIR" >&2
  fi
}
trap cleanup EXIT

"$ROOT/scripts/run_safe.sh" "$COMPILER" 300 4096 \
  "$ROOT/regression_tests/complex/stage2_array_string_to_s_block_proc_repro.cr" \
  --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

if [[ ! -s "$HIR" ]]; then
  echo "p2_block_proc_supply_closure_failed: missing HIR dump" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

missing="$TMP_DIR/missing_block_procs"
awk '
  /func_pointer @__crystal_block_proc_[0-9]+/ {
    name = $0
    sub(/^.*func_pointer @/, "", name)
    sub(/ .*/, "", name)
    refs[name] = 1
  }
  /^func @__crystal_block_proc_[0-9]+\(/ {
    name = $0
    sub(/^func @/, "", name)
    sub(/\(.*/, "", name)
    defs[name] = 1
  }
  END {
    for (name in refs) {
      if (!(name in defs)) print name
    }
  }
' "$HIR" | sort -V >"$missing"

if [[ -s "$missing" ]]; then
  echo "p2_block_proc_supply_closure_failed: dangling FuncPointer targets" >&2
  cat "$missing" >&2
  exit 1
fi

array_to_s_count=$(grep -Ec '^func @Array\(String\)#to_s\$(IO|String::Builder)\(' "$HIR" || true)
if [[ "$array_to_s_count" != "1" ]]; then
  echo "p2_block_proc_supply_closure_failed: expected one Array(String)#to_s body, got $array_to_s_count" >&2
  grep -nE '^func @Array\(String\)#to_s\$(IO|String::Builder)\(' "$HIR" >&2 || true
  exit 1
fi

echo "p2_block_proc_supply_closure_passed"
