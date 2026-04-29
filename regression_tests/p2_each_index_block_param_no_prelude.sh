#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
TMP_DIR="$(mktemp -d /tmp/p2_each_index_block_param_XXXXXX)"
SOURCE="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/compile.log"

cleanup() {
  if [[ "${KEEP_TMP:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "[p2_each_index_block_param_no_prelude] kept tmp: $TMP_DIR" >&2
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "p2_each_index_block_param_no_prelude_failed: compiler not found: $COMPILER" >&2
  exit 2
fi

cat >"$SOURCE" <<'CR'
a = ["x"]
a.each_index { |i| i }
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
  "$SOURCE" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

if [[ ! -s "$OUT.hir" ]]; then
  echo "p2_each_index_block_param_no_prelude_failed: missing HIR output" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q 'Array(String)#each_index\$block' "$OUT.hir"; then
  echo "p2_each_index_block_param_no_prelude_failed: each_index block call missing" >&2
  sed -n '1,80p' "$OUT.hir" >&2
  exit 1
fi

if ! grep -Eq '^func @__crystal_block_proc_[0-9]+\(%[0-9]+: 4\) -> 4' "$OUT.hir"; then
  echo "p2_each_index_block_param_no_prelude_failed: each_index block proc is not Int32-shaped" >&2
  rg -n '__crystal_block_proc|each_index' "$OUT.hir" >&2 || true
  exit 1
fi

if grep -Eq '^func @__crystal_block_proc_[0-9]+\(%[0-9]+: String\)' "$OUT.hir"; then
  echo "p2_each_index_block_param_no_prelude_failed: old String-shaped each_index callback regressed" >&2
  rg -n '__crystal_block_proc|each_index' "$OUT.hir" >&2 || true
  exit 1
fi

echo "p2_each_index_block_param_no_prelude_ok"
