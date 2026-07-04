#!/usr/bin/env bash
# Regression: loop-shaped each-family intrinsics must not clobber a real
# terminator (`return`/`break`/`raise`) in the block body with their
# body-close jump to the increment block (B5 successor-2 root cause).
# Before the fix, `[10,20,30].each { |e| return e }` compiled to a loop that
# ignored the return entirely: the enclosing function ran the loop to
# completion and fell through (printed 0, and code after `each` executed).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/each_intrinsic_block_return.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"

cat > "$SRC" <<'CR'
# A: array-literal each intrinsic, return in block (was: printed 0 + "A-dead")
def a_case
  [10, 20, 30].each { |e| return e }
  puts "A-dead"
  0
end

# B: each_index intrinsic, return in block
def b_case
  [10, 20, 30].each_index { |i| return i + 100 }
  0
end

# C: hash-backed iteration (Set#each) with non-local return via Enumerable
def c_case
  s = Set(String).new
  s << "hello"
  s.first { "empty" }
end

# D: negative — empty enumerable falls through past the loop
def d_case
  ([] of Int32).each { |e| return e }
  7
end

# E: break still leaves the loop early
def e_case
  acc = 0
  [1, 2, 3, 4].each do |e|
    break if e == 3
    acc += e
  end
  acc
end

# F: next still continues the loop
def f_case
  acc = 0
  [1, 2, 3, 4].each do |e|
    next if e == 2
    acc += e
  end
  acc
end

puts a_case
puts b_case
puts c_case
puts d_case
puts e_case
puts f_case
CR

"$COMPILER" "$SRC" -o "$OUT" >"$LOG" 2>&1 || {
  echo "compile failed" >&2
  tail -40 "$LOG" >&2
  exit 1
}

ACTUAL="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
EXPECTED="$(printf '10\n100\nhello\n7\n3\n8')"

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "FAIL: output mismatch" >&2
  echo "--- expected ---" >&2
  echo "$EXPECTED" >&2
  echo "--- actual ---" >&2
  echo "$ACTUAL" >&2
  exit 1
fi

echo "OK: each-family intrinsics preserve block-body terminators (return/break/next)"
