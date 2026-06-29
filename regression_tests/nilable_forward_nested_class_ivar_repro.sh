#!/usr/bin/env bash
# Regression: an ivar annotation may reference a nested class before that nested
# class is registered. The final ivar layout pass must canonicalize the stale
# short union (`Nil | Inner`) to the owner-qualified nested type
# (`Nil | Outer::Inner`) so nilable reference fields are stored as a pointer, not
# as a tagged union copied from a nullable pointer parameter.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nilable_forward_nested_ivar.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro"
LL="$TMP_DIR/repro.ll"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat > "$SRC" <<'CR'
struct Outer
  struct Box
    @inner : Inner?

    def initialize(@inner : Inner? = nil)
    end

    def inner_nil?
      @inner.nil?
    end
  end

  class Inner
  end
end

puts Outer::Box.new.inner_nil?
CR

"$COMPILER" "$SRC" --emit llvm-ir >"$COMPILE_LOG" 2>&1

"$COMPILER" "$SRC" -o "$BIN" >>"$COMPILE_LOG" 2>&1
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1

if ! grep -Fxq "true" "$RUN_LOG"; then
  echo "nilable_forward_nested_class_ivar_repro_failed: runtime output mismatch" >&2
  tail -80 "$COMPILE_LOG" >&2 || true
  tail -80 "$RUN_LOG" >&2 || true
  exit 1
fi

if ! grep -Fq 'define void @Outer$CCBox$Hinitialize$$Nil$_$OR$_Outer$CCInner' "$LL"; then
  echo "nilable_forward_nested_class_ivar_repro_failed: qualified initializer missing" >&2
  tail -80 "$COMPILE_LOG" >&2 || true
  exit 1
fi

if grep -Eq 'call void @llvm\.memcpy\.p0\.p0\.i64\(ptr %r[0-9]+, ptr %inner' "$LL"; then
  echo "nilable_forward_nested_class_ivar_repro_failed: nilable reference field lowered as memcpy" >&2
  grep -n -F 'Outer$CCBox$Hinitialize' "$LL" >&2 || true
  exit 1
fi

if ! grep -Eq 'store ptr %inner, ptr %r[0-9]+' "$LL"; then
  echo "nilable_forward_nested_class_ivar_repro_failed: pointer field store missing" >&2
  grep -n -F 'Outer$CCBox$Hinitialize' "$LL" >&2 || true
  exit 1
fi

echo "nilable_forward_nested_class_ivar_repro_ok"
