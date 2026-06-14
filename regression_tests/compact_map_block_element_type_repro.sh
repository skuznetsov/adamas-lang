#!/usr/bin/env bash
# Regression test: Array#compact_map { ... } must infer its result element type
# from the (nil-stripped) block return type, NOT degrade it to Pointer(Void).
#
# Bug: compact_map had no intrinsic, so it fell through to the stdlib body
#   ary = [] of typeof((yield element).not_nil!)
# and V2's `typeof(...not_nil!)` inference degraded the result element type to
# Pointer(Void). A subsequent `.reject(&.empty?)` on the result then resolved to
# `Pointer(Void)#empty?` -> "STUB CALLED: Pointer(Void)#empty?" / abort (134).
# This was the dominant non-deterministic s2b crash, reached via
# canonical_named_arg_names$Array(Pointer(Void)) <- named_arg_names_for.
#
# Fix: lower_array_compact_map_dynamic intrinsic (mirrors map/select/reject) that
# collects non-nil block results into a new array whose element type is the block
# return type with Nil removed.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/compact_map_elem.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

fail=0
run_case() {
  local name="$1" src="$2" expect="$3"
  local cr="$TMP_DIR/$name.cr" bin="$TMP_DIR/$name.bin" out="$TMP_DIR/$name.out"
  printf '%s' "$src" >"$cr"
  if ! "$COMPILER" "$cr" -o "$bin" >"$TMP_DIR/$name.compile" 2>&1; then
    echo "FAIL[$name]: compile error"; cat "$TMP_DIR/$name.compile"; fail=1; return
  fi
  # Read results from STDERR — V2 binaries can truncate the last STDOUT write
  # on normal exit (program-exit-stdio-flush-truncation-bug).
  "$bin" >/dev/null 2>"$out" || true
  local got; got="$(cat "$out")"
  if [[ "$got" == "$expect" ]]; then
    echo "PASS[$name]: [$got]"
  else
    echo "FAIL[$name]: expected [$expect] got [$got]"; fail=1
  fi
}

# Core bug: compact_map { String? } chained into .reject(&.empty?).
# Was: STUB CALLED Pointer(Void)#empty? (abort 134).
run_case compact_map_reject 'arr = [1, 2, 3]
names = arr.compact_map do |s|
  s > 1 ? "x" : nil
end
STDERR.puts names.reject(&.empty?).size' "2"

# Cross-function shape (mirrors named_arg_names_for -> canonical_named_arg_names):
# function A returns the compact_map result; function B consumes it with
# .reject(&.empty?). A's return type must be Array(String) so B's &.empty?
# resolves to String#empty?, not Pointer(Void)#empty?.
run_case compact_map_cross_fn 'def names_for(arr : Array(Int32)) : Array(String)
  arr.compact_map do |e|
    e > 1 ? "x" : nil
  end
end
def canonical(names : Array(String)) : Array(String)
  names.reject(&.empty?)
end
STDERR.puts canonical(names_for([1, 2, 3])).size' "2"

# Non-nilable block result: every element is pushed (control for the always-push
# path where the nil-check is a literal false).
run_case compact_map_non_nilable 'arr = [1, 2, 3]
names = arr.compact_map { |s| "n#{s}" }
STDERR.puts names.size
STDERR.puts names.reject(&.empty?).size' "3
3"

# All-nil results: produces an empty array (count 0), no crash.
run_case compact_map_all_nil 'arr = [1, 2, 3]
names = arr.compact_map { |s| s > 100 ? "x" : nil }
STDERR.puts names.size' "0"

if [[ $fail -eq 0 ]]; then
  echo "reproduced: compact_map infers nil-stripped block element type"
  exit 0
else
  echo "NOT FIXED: compact_map result element type degraded to Pointer(Void)"
  exit 1
fi
