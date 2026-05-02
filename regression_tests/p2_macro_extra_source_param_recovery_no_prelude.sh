#!/usr/bin/env bash
# No-prelude guard for macro-expanded parameter source recovery.
# Macro outputs are reparsed into the macro definition arena; parameter spans
# must be sliced from retained generated output, not from src/stdlib/macros.cr
# or the macro body source.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_macro_param_source_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/macro_param_source.cr"
OUT="$TMP_DIR/macro_param_source"
LOG="$TMP_DIR/macro_param_source.log"

cat >"$SRC" <<'CR'
class Object
end

macro make_box
  class Box
    def initialize(@name : String, @total_size : Int32, @source_line : Int32? = nil)
    end
  end
end

make_box
Box.new("x", 1)
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 1024 \
  "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

if ! grep -Fq 'func @Box#initialize$String_Int32_Nil | Int32' "$OUT.hir"; then
  echo "p2 macro param source regression: missing generated initialize signature" >&2
  cat "$LOG" >&2
  cat "$OUT.hir" >&2
  exit 1
fi

if ! grep -Fq 'field_set %0.@@total_size' "$OUT.hir"; then
  echo "p2 macro param source regression: missing @total_size initializer field_set" >&2
  cat "$LOG" >&2
  cat "$OUT.hir" >&2
  exit 1
fi

if ! grep -Fq 'field_set %0.@@source_line' "$OUT.hir"; then
  echo "p2 macro param source regression: missing @source_line initializer field_set" >&2
  cat "$LOG" >&2
  cat "$OUT.hir" >&2
  exit 1
fi

if grep -Fq 'ass Bo_lize_total_' "$OUT.hir" ||
   grep -Fq '@@def ini' "$OUT.hir" ||
   grep -Fq '@@ame : String' "$OUT.hir"; then
  echo "p2 macro param source regression: stale macro-source slices leaked into HIR" >&2
  cat "$LOG" >&2
  cat "$OUT.hir" >&2
  exit 1
fi

echo "p2_macro_extra_source_param_recovery_no_prelude_ok"
