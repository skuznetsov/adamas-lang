#!/usr/bin/env bash
# Guard no-prelude LLVM emission against duplicate alloca SSA names.
#
# This catches the stage2-only failure where MIR stack Alloc instructions were
# hoisted once by the entry prepass and then hoisted again from buffered block IR.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SRC="$ROOT_DIR/regression_tests/combined/test_no_prelude_interpolation.cr"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_unique_alloca_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT="$TMP_DIR/noprel"
LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
  "$SRC" --no-prelude -o "$OUT" >"$LOG" 2>&1

LL="$OUT.ll"
if [[ ! -s "$LL" ]]; then
  echo "p2 no-prelude unique alloca regression: missing LLVM artifact" >&2
  cat "$LOG" >&2
  exit 1
fi

dups="$(
  awk '
    /^define / {
      for (name in count) {
        if (count[name] > 1) {
          print current " " name " " count[name]
        }
      }
      delete count
      current = $0
    }
    /^[[:space:]]*%[^[:space:]]+ = alloca / {
      name = $1
      count[name] += 1
    }
    END {
      for (name in count) {
        if (count[name] > 1) {
          print current " " name " " count[name]
        }
      }
    }
  ' "$LL"
)"

if [[ -n "$dups" ]]; then
  echo "p2 no-prelude unique alloca regression: duplicate alloca SSA names" >&2
  echo "$dups" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 256 >"$RUN_LOG" 2>&1
if ! grep -q "noprelude_interp_ok" "$RUN_LOG"; then
  echo "p2 no-prelude unique alloca regression: compiled binary did not run" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "p2_no_prelude_unique_alloca_names_ok"
