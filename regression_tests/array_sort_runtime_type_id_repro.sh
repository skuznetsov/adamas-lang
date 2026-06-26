#!/usr/bin/env bash
# Regression: Array#sort lowered through the dup+sort intrinsic must preserve the
# Array(T) runtime type_id header. HIR TypeRef ids and MIR/runtime type ids are
# different namespaces; baking the raw HIR id into the sorted copy makes
# `String | Array(String) | Nil` dispatch miss the Array branch.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array_sort_tid.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$SRC" <<'CR'
files = [] of String
files << "z"
files << "a"
sorted = files.sort

files_ref = pointerof(files).as(Pointer(UInt64)).value
sorted_ref = pointerof(sorted).as(Pointer(UInt64)).value
files_tid = Pointer(Int32).new(files_ref).value
sorted_tid = Pointer(Int32).new(sorted_ref).value
puts "TIDS=#{files_tid},#{sorted_tid}"

resolved = sorted.as(String | Array(String) | Nil)
case resolved
when Array
  puts "CASE=Array size=#{resolved.size} first=#{resolved[0]}"
else
  puts "CASE=Miss"
end
puts "ISA=#{resolved.is_a?(Array(String))},#{resolved.is_a?(Array)}"
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 2048 "$SRC" -o "$BIN" >"$COMPILE_LOG" 2>&1
compile_status=$?
set -e
if [[ $compile_status -ne 0 ]]; then
  echo "FAIL: compile failed (status $compile_status)" >&2
  tail -120 "$COMPILE_LOG" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1

tids="$(grep -E '^TIDS=' "$RUN_LOG" | head -1 | cut -d= -f2)"
if [[ -z "$tids" ]]; then
  echo "FAIL: missing TIDS output" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi
IFS=, read -r files_tid sorted_tid <<<"$tids"
if [[ "$files_tid" != "$sorted_tid" ]]; then
  echo "FAIL: Array#sort changed runtime type_id header: $files_tid -> $sorted_tid" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

if ! grep -Fq "CASE=Array size=2 first=a" "$RUN_LOG"; then
  echo "FAIL: sorted Array(String) did not dispatch through the Array union branch" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

if ! grep -Fq "ISA=true,true" "$RUN_LOG"; then
  echo "FAIL: sorted Array(String) failed Array type checks" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "array_sort_runtime_type_id_ok tid=$files_tid"
