#!/usr/bin/env bash
# Bloat guard for the bare-Tuple Object#in?(*values : Object) broadcast path.
# Companion to the semantic test `object_in_splat_broadcast.cr` and the fix
# commit 28036d5c. Regressing the fix (reintroducing the bare-Tuple struct
# fallback) causes `Tuple#includes?$X` to be emitted per reachable receiver X.
# Measured deltas on the same source file:
#   pre-fix (28036d5c^): 218 Tuple#includes? defines
#   post-fix (HEAD):       4 Tuple#includes? defines
#
# This script compiles the sibling .cr with `--emit llvm-ir` and asserts the
# final define count stays below a conservative threshold. 20 is chosen to
# catch reintroducing the hundreds-of-bodies burst while tolerating small
# legitimate growth from future stdlib changes.
#
# Exit contract:
#   0 — count < threshold (fix intact).
#   1 — count >= threshold (regression detected).
#   2 — invalid invocation.
#   >2 — unexpected failure (compile error, missing IR, etc.).
set -euo pipefail

THRESHOLD=20
SRC_REL="regression_tests/object_in_splat_broadcast.cr"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SRC="$ROOT_DIR/$SRC_REL"

if [[ ! -f "$SRC" ]]; then
  echo "unexpected: source not found: $SRC" >&2
  exit 3
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/object_in_splat_hir_count.XXXXXX")"
OUT_STEM="$TMP_DIR/probe"
COMPILE_LOG="$TMP_DIR/compile.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

compile_cmd=()
if [[ "$(basename "$COMPILER")" == "crystal" ]]; then
  compile_cmd=("$COMPILER" build "$SRC" --emit llvm-ir -o "$OUT_STEM")
else
  compile_cmd=("$COMPILER" "$SRC" --emit llvm-ir -o "$OUT_STEM")
fi

set +e
"${compile_cmd[@]}" >"$COMPILE_LOG" 2>&1
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "unexpected: compile failed with status=$compile_status" >&2
  tail -20 "$COMPILE_LOG" >&2
  exit 4
fi

IR="$OUT_STEM.ll"
if [[ ! -f "$IR" ]]; then
  echo "unexpected: LLVM IR not emitted at $IR" >&2
  ls -la "$TMP_DIR" >&2
  exit 5
fi

count=$(grep -c '^define.*Tuple\$Hincludes' "$IR" || true)
: "${count:=0}"

echo "Tuple#includes? defines: $count (threshold < $THRESHOLD)"

if (( count >= THRESHOLD )); then
  echo "regression: bare-Tuple Object#in?(*values) bloat likely reintroduced" >&2
  echo "expected < $THRESHOLD, got $count" >&2
  exit 1
fi

echo "ok: fix intact"
exit 0
