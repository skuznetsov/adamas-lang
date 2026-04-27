#!/usr/bin/env bash
# Regression: abstract class method dispatch must be synthesized in MIR,
# never hardcoded in the LLVM backend.
#
# Background:
#   Bare `__vdispatch__<C>$H<m>` tables for abstract methods used to be
#   produced only as a side effect of `ensure_class_dispatch_for_union`.
#   When the union dispatch path never fired, callers of `<C>#<m>` linked
#   against a stub fabricated by the LLVM backend that referenced a
#   hardcoded T-suffixed dispatch symbol (e.g. `...$Node$Hspan$T623`).
#   That symbol was unrelated to any real type registration, and the IR
#   failed to assemble with `use of undefined value '@__vdispatch__...$T623'`.
#
# Fix:
#   - `synthesize_abstract_method_dispatchers` (hir_to_mir.cr) materialises
#     a real MIR dispatch body for every `<C>#<m>` whose subclasses define
#     an override but the class itself does not, so the canonical symbol
#     resolves on its own.
#   - The hardcoded T623 fallback was removed from `emit_dead_code_stub`.
#
# This test asserts both invariants structurally and runs a tiny program
# that exercises the synthesizer end-to-end.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
LLVM_BACKEND="$ROOT_DIR/src/compiler/mir/llvm_backend.cr"
HIR_TO_MIR="$ROOT_DIR/src/compiler/mir/hir_to_mir.cr"
TMP_DIR="$(mktemp -d /tmp/abstract_class_method_dispatch_synth_XXXXXX)"
SOURCE="$TMP_DIR/repro.cr"
OUT_BIN="$TMP_DIR/repro_bin"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  if [[ "${KEEP_TMP:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "[abstract_class_method_dispatch_synth] kept tmp: $TMP_DIR" >&2
  fi
}
trap cleanup EXIT

# Structural guard 1: the hardcoded fallback that referenced a nonexistent
# T-suffixed vdispatch symbol must stay deleted.
if grep -nF '__vdispatch__CrystalV2$CCCompiler$CCFrontend$CCNode$Hspan$$T' "$LLVM_BACKEND" >/dev/null; then
  echo "abstract_class_method_dispatch_synth_failed: hardcoded Node\$Hspan vdispatch fallback reintroduced in llvm_backend.cr" >&2
  grep -nF '__vdispatch__CrystalV2$CCCompiler$CCFrontend$CCNode$Hspan$$T' "$LLVM_BACKEND" >&2
  exit 1
fi

# Structural guard 2: synthesizer must still be in place.
if ! grep -q 'synthesize_abstract_method_dispatchers' "$HIR_TO_MIR"; then
  echo "abstract_class_method_dispatch_synth_failed: synthesize_abstract_method_dispatchers removed from hir_to_mir.cr" >&2
  exit 1
fi

if [[ ! -x "$COMPILER" ]]; then
  echo "abstract_class_method_dispatch_synth_failed: compiler not found: $COMPILER" >&2
  exit 2
fi

cat >"$SOURCE" <<'CR'
abstract class Shape
  abstract def label : String
end

class Circle < Shape
  def label : String
    "circle"
  end
end

class Square < Shape
  def label : String
    "square"
  end
end

shapes = [Circle.new.as(Shape), Square.new.as(Shape)]
shapes.each do |s|
  puts s.label
end
CR

"$COMPILER" "$SOURCE" -o "$OUT_BIN" >"$COMPILE_LOG" 2>&1

if [[ ! -x "$OUT_BIN" ]]; then
  echo "abstract_class_method_dispatch_synth_failed: compiler did not produce binary" >&2
  tail -80 "$COMPILE_LOG" >&2 || true
  exit 1
fi

if grep -q "use of undefined value" "$COMPILE_LOG"; then
  echo "abstract_class_method_dispatch_synth_failed: LLVM reported undefined value" >&2
  grep "use of undefined value" "$COMPILE_LOG" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$OUT_BIN" 5 256 >"$RUN_LOG" 2>&1

if grep -q "STUB CALLED" "$RUN_LOG"; then
  echo "abstract_class_method_dispatch_synth_failed: abstract dispatch fell through to STUB CALLED" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

if grep -qx 'circle' "$RUN_LOG" && grep -qx 'square' "$RUN_LOG"; then
  echo "abstract_class_method_dispatch_synth_ok"
  exit 0
fi

echo "abstract_class_method_dispatch_synth_failed: unexpected runtime output" >&2
cat "$RUN_LOG" >&2
exit 1
