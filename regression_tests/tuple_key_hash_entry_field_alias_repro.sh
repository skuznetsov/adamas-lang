#!/usr/bin/env bash
# `key.hash` on a Tuple(A, B) receiver must call Tuple#hash. A legacy special
# case in lower_member_access rewrote it to a FieldGet of `@hash` from
# Hash::Entry(A, B) whenever that Entry type existed in the program, so
# Hash(Tuple(UInt32, UInt32), _)#key_hash read garbage at key+8 once a
# Hash(UInt32, UInt32) was also instantiated. Sets/Hashes above 16 entries
# (indexed lookup) then missed keys; in S2 this dropped entries of
# @control_flow_dead_blocks and broke `next unless` dead-branch detection.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tuple_key_hash_entry_field_alias_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
h = Hash(UInt32, UInt32).new
h[1_u32] = 2_u32
h.each { |k, v| STDERR.puts "h=#{k},#{v}" }
s = Set({UInt32, UInt32}).new
i = 0_u32
while i < 40_u32
  s.add({7_u32, i}); i += 1
end
def chk(s : Set({UInt32, UInt32}), a : UInt32, b : UInt32) : Bool
  s.includes?({a, b})
end
miss = 0
j = 0_u32
while j < 40_u32
  miss += 1 unless chk(s, 7_u32, j)
  j += 1
end
STDERR.puts "miss=#{miss} size=#{s.size}"
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -qx 'miss=0 size=40' "$WORK_DIR/run.log"; then
  cat "$WORK_DIR/run.log" >&2
  echo "FAIL: Tuple#hash lowered as Hash::Entry @hash field read" >&2
  exit 1
fi
echo "PASS: Tuple key hash calls Tuple#hash"
