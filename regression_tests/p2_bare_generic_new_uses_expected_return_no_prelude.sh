#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/p2_bare_generic_new.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"
METHOD_HIR="$TMP_DIR/to_bag.hir"

cat > "$SRC" <<'CR'
module M(T)
end

module M
  def to_bag : Bag(T)
    Bag.new(self)
  end
end

class Bag(T)
  def initialize(other)
  end
end

class A(T)
  include M(T)
end

a = A(String).new
a.to_bag
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 \
  "$SRC" --no-prelude --emit=hir --no-link -o "$OUT" >"$LOG" 2>&1

HIR="$OUT.hir"
if [[ ! -f "$HIR" ]]; then
  echo "missing HIR output" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

awk '
  /^func @A\(String\)#to_bag/ { inside = 1 }
  inside { print }
  inside && /^}/ { exit }
' "$HIR" > "$METHOD_HIR"

if [[ ! -s "$METHOD_HIR" ]]; then
  echo "missing A(String)#to_bag HIR" >&2
  rg -n 'to_bag|Bag\(' "$HIR" >&2 || true
  exit 1
fi

if grep -q 'Bag(A(String)).new' "$METHOD_HIR"; then
  echo "bare generic .new inferred the receiver object type instead of the expected generic return type" >&2
  cat "$METHOD_HIR" >&2
  exit 1
fi

if ! grep -q 'Bag(String).new[$]A(String)' "$METHOD_HIR"; then
  echo "bare generic .new did not specialize to Bag(String)" >&2
  cat "$METHOD_HIR" >&2
  exit 1
fi

echo "p2_bare_generic_new_uses_expected_return_no_prelude_ok"
