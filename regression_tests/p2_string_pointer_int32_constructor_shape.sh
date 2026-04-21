#!/usr/bin/env bash
# LLVM shape guard: String.new(UInt8*, Int32) must delegate to the
# header-setting UInt8*, Int32, Int32 runtime override.
#
# Regression shape:
#   String.new(Slice(UInt8))
#
# The stdlib Slice constructor calls String.new(slice.to_unsafe, bytesize).
# In V2 this materializes a distinct default-argument overload named
# String$Dnew$$Pointer$LUInt8$R_Int32. If that body is lowered normally it
# goes through String.new(capacity) + GC.malloc_atomic and can return a raw
# buffer without the V2 String object header. During self-hosting this corrupts
# compiler-owned string literals before LLVM string interning sees them.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_string_pointer_ctor_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/string_pointer_ctor.cr"
OUT="$TMP_DIR/string_pointer_ctor"
LOG="$TMP_DIR/compile.log"
LL="$OUT.ll"

cat >"$SRC" <<'CR'
bytes = Slice.new("abc".to_unsafe, 3)
str = String.new(bytes)
puts str
CR

LIBRARY_PATH="${LIBRARY_PATH:-/opt/homebrew/lib}" \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 \
    "$SRC" --emit llvm-ir --no-link -o "$OUT" >"$LOG" 2>&1

if [[ ! -s "$LL" ]]; then
  echo "p2 string pointer constructor regression: missing LLVM artifact" >&2
  cat "$LOG" >&2
  exit 1
fi

BODY="$TMP_DIR/string_pointer_int32_body.ll"
awk '
  /^define ptr @String\$Dnew\$\$Pointer\$LUInt8\$R_Int32\(/ {in_body=1}
  in_body {print}
  in_body && /^}$/ {exit}
' "$LL" >"$BODY"

if [[ ! -s "$BODY" ]]; then
  echo "p2 string pointer constructor regression: missing String.new(UInt8*, Int32) body" >&2
  exit 1
fi

if ! grep -q 'String\$Dnew\$\$Pointer\$LUInt8\$R_Int32_Int32' "$BODY"; then
  echo "p2 string pointer constructor regression: body does not delegate to Int32_Int32 override" >&2
  cat "$BODY" >&2
  exit 1
fi

if grep -q 'GC\$Dmalloc_atomic' "$BODY"; then
  echo "p2 string pointer constructor regression: body still allocates through GC.malloc_atomic" >&2
  cat "$BODY" >&2
  exit 1
fi

echo "p2_string_pointer_int32_constructor_shape_ok"
