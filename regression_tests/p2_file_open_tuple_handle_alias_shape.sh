#!/usr/bin/env bash
# Guard full-prelude tuple element lowering for FileDescriptor::Handle aliases.
#
# Crystal::System::File.open returns {FileDescriptor::Handle, Bool}. On Unix the
# handle is an Int32 alias, but it can be observed from File.new_internal through
# another namespace as File::FileDescriptor::Handle. The tuple element must still
# lower as a scalar i32 load, not as a pointer load followed by fd dereference.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TIMEOUT_SEC="${P2_FILE_OPEN_TUPLE_TIMEOUT_SEC:-60}"
MEM_MB="${P2_FILE_OPEN_TUPLE_MEM_MB:-2048}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_file_open_tuple_alias_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/out"
LL="$OUT.ll"
LOG="$TMP_DIR/compile.log"
BODY="$TMP_DIR/file_new_internal.ll"

cat >"$SRC" <<'CR'
def probe(path : String)
  File.open(path) do |file|
    file.read(Bytes.new(1))
  end
end

probe("/tmp/nope")
CR

CRYSTAL_V2_STOP_AFTER_LLVM=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
    "$SRC" --no-link --emit llvm-ir -o "$OUT" >"$LOG" 2>&1

if [[ ! -s "$LL" ]]; then
  echo "p2 file-open tuple alias regression: missing LLVM artifact" >&2
  tail -80 "$LOG" >&2
  exit 1
fi

awk '
  index($0, "define ptr @File$Dnew_internal$$String_String_File$CCPermissions_Nil_Nil_Nil(") == 1 { in_body = 1 }
  in_body { print }
  in_body && $0 == "}" { exit }
' "$LL" >"$BODY"

if [[ ! -s "$BODY" ]]; then
  echo "p2 file-open tuple alias regression: missing File.new_internal body" >&2
  exit 1
fi

if grep -Eq '= load ptr, ptr %[A-Za-z0-9_.]+\.elem_ptr' "$BODY"; then
  echo "p2 file-open tuple alias regression: fd tuple element lowered as pointer" >&2
  cat "$BODY" >&2
  exit 1
fi

if ! grep -Eq '= load i32, ptr %[A-Za-z0-9_.]+\.elem_ptr' "$BODY"; then
  echo "p2 file-open tuple alias regression: missing scalar i32 tuple load" >&2
  cat "$BODY" >&2
  exit 1
fi

if ! grep -q '@File$Dnew$$String_Int32_String_Bool_Nil_Nil' "$BODY"; then
  echo "p2 file-open tuple alias regression: File.new did not receive scalar Int32/Bool args" >&2
  cat "$BODY" >&2
  exit 1
fi

echo "p2_file_open_tuple_handle_alias_shape_ok"
