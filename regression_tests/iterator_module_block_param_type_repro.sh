#!/usr/bin/env bash
# Repro: block-param types for module-owned generic methods reached through an
# include chain (String#each_char -> String::CharIterator -> Iterator(Char) ->
# Enumerable(T)#all?).
#
# Root cause (fixed): include-site instantiations were dropped at registration
# (@class_included_modules only held declared names like "Iterator(T)"), so
# block_param_types_for_call could not bind T for a receiver whose own name
# carries no generic args (String::CharIterator). The `& : T ->` annotation
# passed through unsubstituted, the block proc was typed `T` (opaque pointer),
# and the block body called the abort stub `T#ascii_number?`. This was the L6
# s2 self-host floor: AstToHir#numeric_conversion_method_name? aborts ~2s into
# any s2 compile.
#
# GREEN: shorthand and explicit blocks on each_char.all?/any? resolve Char.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/iter_block_param.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat > "$SRC" <<'CR'
s = "123"
STDERR.puts "a=#{s.each_char.all?(&.ascii_number?)}"
s2 = "12a"
STDERR.puts "b=#{s2.each_char.all?(&.ascii_number?)}"
STDERR.puts "c=#{s.each_char.all? { |c| c.ascii_number? }}"
STDERR.puts "d=#{s2.each_char.any?(&.ascii_letter?)}"
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
  "$SRC" -o "$OUT" >"$LOG" 2>&1

"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$RUN_LOG" 2>&1 || true

fail=0
for expect in "a=true" "b=false" "c=true" "d=true"; do
  grep -q "^$expect\$" "$RUN_LOG" || { echo "RED: missing '$expect'"; fail=1; }
done
if grep -q "STUB CALLED" "$RUN_LOG"; then
  echo "RED: abort stub called"
  fail=1
fi

if [[ "$fail" != "0" ]]; then
  echo "--- run log ---"
  cat "$RUN_LOG"
  exit 1
fi

echo "PASS: include-chain block-param types resolve (each_char.all?/any?)"
