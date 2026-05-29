#!/usr/bin/env bash
# HIR no-prelude guard: Array(Struct)#unsafe_fetch must carry the element type.
#
# Regression shape:
#   e = ([] of Entry).unsafe_fetch(0)
#   e.type_id
#
# The root failure froze unsafe_fetch as VOID, so the later getter call was
# typed from syntax rather than from the fetched value. In full bootstrap this
# surfaced as UInt64#type_id during type metadata emission.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_array_struct_fetch_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/array_struct_fetch.cr"
OUT="$TMP_DIR/array_struct_fetch"
LOG="$TMP_DIR/run_safe.log"
HIR="$OUT.hir"

cat >"$SRC" <<'CR'
struct Entry
  def initialize(@type_id : UInt32)
  end

  def type_id : UInt32
    @type_id
  end
end

arr = [] of Entry
arr << Entry.new(7_u32)
e = arr.unsafe_fetch(0)
puts e.type_id
CR

CRYSTAL_V2_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 1024 \
    "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

if [[ ! -s "$HIR" ]]; then
  echo "p2 array struct unsafe_fetch regression: missing HIR artifact" >&2
  cat "$LOG" >&2
  exit 1
fi

if grep -Eq 'Array\(Entry\)#unsafe_fetch\$Int32\([^)]*\) : 0' "$HIR"; then
  echo "p2 array struct unsafe_fetch regression: unsafe_fetch returned VOID" >&2
  grep -n 'Array(Entry)#unsafe_fetch' "$HIR" >&2 || true
  exit 1
fi

if ! grep -Eq 'Array\(Entry\)#unsafe_fetch\$Int32\([^)]*\) : [1-9][0-9]*' "$HIR"; then
  echo "p2 array struct unsafe_fetch regression: unsafe_fetch call missing typed return" >&2
  grep -n 'unsafe_fetch' "$HIR" >&2 || true
  exit 1
fi

if ! grep -Eq 'field_get .*@@type_id' "$HIR"; then
  echo "p2 array struct unsafe_fetch regression: Entry#type_id was not reduced to field_get" >&2
  grep -n 'type_id' "$HIR" >&2 || true
  exit 1
fi

echo "p2_array_struct_unsafe_fetch_return_no_prelude_ok"
