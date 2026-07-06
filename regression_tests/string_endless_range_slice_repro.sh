#!/usr/bin/env bash
# Repro: String endless-range slicing s[1..] must not return "".
#
# Root cause (fixed): the String#[](Range) compiler intercept lowered the
# slice inline as len = end - begin (+1) with NO endless-range handling; the
# parser stores a NilNode end for `s[1..]`, the nil lowered to 0, so
# len = 0 - begin + 1 (= 0 for begin 1) and the slice came back empty. This
# fed the L5 s2 floor: llvm_backend's "i64"[1..] returned "" so the
# arg-coercion src_bits guard evaluated wrong inside s2 (llc `sext i64 to i64`).
#
# GREEN: endless/beginless/negative/explicit range forms all slice correctly,
# for both literal and variable begin, plus Array#[1..].
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/endless_range.XXXXXX")"
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
s = "hello"
STDERR.puts "a=#{s[0..]}"
STDERR.puts "b=#{s[2..]}"
STDERR.puts "c=#{s[5..]}."
STDERR.puts "d=#{s[1...]}"
STDERR.puts "e=#{s[..1]}"
STDERR.puts "f=#{s[1..-1]}"
STDERR.puts "g=#{s[1..3]}"
i = 2
STDERR.puts "h=#{s[i..]}"
arr = [10, 20, 30]
t = arr[1..]
STDERR.puts "i=#{t.size}"
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
  "$SRC" -o "$OUT" >"$LOG" 2>&1

"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$RUN_LOG" 2>&1 || true

fail=0
for expect in "a=hello" "b=llo" "c=." "d=ello" "e=he" "f=ello" "g=ell" "h=llo" "i=2"; do
  grep -q "^$expect\$" "$RUN_LOG" || { echo "RED: missing '$expect'"; fail=1; }
done

if [[ "$fail" != "0" ]]; then
  echo "--- run log ---"
  cat "$RUN_LOG"
  exit 1
fi

echo "PASS: endless-range slicing correct (String literal/variable begin + Array)"
