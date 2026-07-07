#!/usr/bin/env bash
# Repro: tuple-destructured block params on array intrinsics —
# `arr.map { |(a, b)| ... }` and friends.
#
# Root cause (fixed): the parser flattens `|(a, b)|` into flat params [a, b];
# array intrinsic lowerings bind ONE element per iteration, and
# each/any/all re-expanded the flat params to tuple element extracts while
# map/map_with_index/select/reject/compact_map/sum/count bound ONLY the first
# param name to the whole tuple element (second name left unbound). Downstream
# the first param dispatched Tuple methods (`a + 1` → Tuple#+ abort stub) and
# lookups on the unbound name silently returned nil/garbage.
#
# This was the L8 s2 self-host floor: merge_if_branch_locals in the compiler
# itself does `branch_info.map { |(blk, locals)| ... }`-style destructuring;
# in the miscompiled s2 the branch-locals hash lookups returned nil, the
# is_a?-branch reassignment merge for `part` in Path#join reverted to the
# union param, and s2 emitted a spurious
# "private method 'empty?' called for Path | String" on ANY prelude compile.
#
# GREEN: destructured intrinsic blocks behave like their explicit-index forms.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arr_destr.XXXXXX")"
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
pairs = [] of Tuple(Int32, Int32)
pairs << {1, 10}
pairs << {2, 20}
pairs << {3, 30}

# map — the L8 shape
m = pairs.map { |(a, b)| a + b }
STDERR.puts "map=#{m.join(",")}"

# map over Tuple(Int32, Hash) — the exact merge_if_branch_locals shape
infos = [] of Tuple(Int32, Hash(String, Int32))
infos << {100, {"part" => 9}}
infos << {200, {"part" => 13}}
mh = infos.map { |(blk, locals)| "b#{blk}=#{locals["part"]? || "-"}" }
STDERR.puts "maph=#{mh.join(" ")}"

# select / reject / count
s = pairs.select { |(a, b)| b > 15 }
STDERR.puts "select=#{s.size}"
r = pairs.reject { |(a, b)| b > 15 }
STDERR.puts "reject=#{r.size}"
c = pairs.count { |(a, b)| a >= 2 }
STDERR.puts "count=#{c}"

# sum
sm = pairs.sum { |(a, b)| b }
STDERR.puts "sum=#{sm}"

# compact_map
cm = pairs.compact_map { |(a, b)| b > 15 ? a : nil }
STDERR.puts "compact_map=#{cm.join(",")}"

# map_with_index with destructure: |(a, b), idx|
mwi = pairs.map_with_index { |(a, b), idx| a * 100 + b + idx }
STDERR.puts "mwi=#{mwi.join(",")}"

# plain two-param map_with_index still works
mwi2 = pairs.map_with_index { |pair, idx| pair[0] + idx }
STDERR.puts "mwi2=#{mwi2.join(",")}"

# each (was already green) — guard against regression
acc = 0
pairs.each { |(a, b)| acc += b }
STDERR.puts "each=#{acc}"
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
  "$SRC" -o "$OUT" >"$LOG" 2>&1

"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$RUN_LOG" 2>&1 || true

fail=0
for expect in "map=11,22,33" "maph=b100=9 b200=13" "select=2" "reject=1" \
              "count=2" "sum=60" "compact_map=2,3" "mwi=110,221,332" \
              "mwi2=1,3,5" "each=60"; do
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

echo "PASS: array intrinsics expand tuple-destructured block params"
