#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/p2_nilable_proc_union.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"
FETCH_HIR="$TMP_DIR/fetch.hir"

cat > "$SRC" <<'CR'
class Box(K, V)
  @block : (self, K -> V)?

  def initialize
    @block = nil
  end

  def fetch(key)
    if block = @block
      block.call(self, key)
    else
      key
    end
  end
end

b = Box(String, Int32).new
b.fetch("x")
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 \
  "$SRC" --no-prelude --emit=hir --no-link -o "$OUT" >"$LOG" 2>&1

HIR="$OUT.hir"
if [[ ! -f "$HIR" ]]; then
  echo "missing HIR output" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if grep -q 'Union Nil | Proc$' "$HIR"; then
  echo "nilable proc annotation lost its Proc signature" >&2
  rg -n 'Union Nil \| Proc' "$HIR" >&2 || true
  exit 1
fi

if ! grep -q 'Union Nil | Proc(Box(String, Int32), String, Int32)' "$HIR"; then
  echo "missing typed nilable proc union for Box(String, Int32)" >&2
  rg -n 'Union Nil \| Proc|Proc\(Box\(String, Int32\)' "$HIR" >&2 || true
  exit 1
fi

awk '
  /^func @Box\(String, Int32\)#fetch[$]String/ { inside = 1 }
  inside { print }
  inside && /^}/ { exit }
' "$HIR" > "$FETCH_HIR"

if [[ ! -s "$FETCH_HIR" ]]; then
  echo "missing Box(String, Int32)#fetch$String HIR" >&2
  rg -n 'Box\(String, Int32\)#fetch' "$HIR" >&2 || true
  exit 1
fi

if grep -q 'Proc#call.* : 0' "$FETCH_HIR"; then
  echo "typed Proc#call return collapsed to Void" >&2
  cat "$FETCH_HIR" >&2
  exit 1
fi

if ! grep -q 'Proc#call.* : 4' "$FETCH_HIR"; then
  echo "typed Proc#call did not return Int32" >&2
  cat "$FETCH_HIR" >&2
  exit 1
fi

echo "p2_nilable_proc_union_preserves_signature_no_prelude_ok"
