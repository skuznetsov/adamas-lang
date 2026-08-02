#!/usr/bin/env bash
# Runtime oracle for instance-dependent returns dispatched through a bare
# reference-generic receiver. The HIR call ABI must cover every registered
# concrete instance instead of inheriting the first union variant's return.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bare_generic_union_return.XXXXXX")"

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"

cat >"$SRC" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

class LayoutBox(T)
  getter payload : T

  def initialize(@payload : T)
  end
end

def choose_box(flag : Bool) : LayoutBox(Int32) | LayoutBox(String)
  if flag
    LayoutBox(Int32).new(7)
  else
    LayoutBox(String).new("x")
  end
end

def erased_payload(value : LayoutBox)
  value.payload
end

first = erased_payload(choose_box(true))
first_ok = case first
           when Int32
             first == 7
           when String
             false
           end

second = erased_payload(choose_box(false))
second_ok = case second
            when Int32
              false
            when String
              second == "x"
            end

if first_ok && second_ok
  LibC.printf("OK\n")
else
  LibC.printf("BAD\n")
end
CR

if ! "$COMPILER" "$SRC" -o "$OUT" >"$TMP_DIR/compile.log" 2>&1; then
  echo "FAIL: compile error" >&2
  tail -20 "$TMP_DIR/compile.log" >&2
  exit 1
fi

RAW="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null)"
GOT="$(printf '%s\n' "$RAW" | sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/p' | sed '1d;$d')"

if [[ "$GOT" != "OK" ]]; then
  echo "FAIL: bare generic union return ABI (expected 'OK', got '$GOT')" >&2
  exit 1
fi

echo "PASS: bare generic union return ABI preserves every concrete result"
