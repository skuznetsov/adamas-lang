#!/usr/bin/env bash
# Regression: Hash#delete / #put with a Tuple key returned the cleared / new
# slot value. The inline-container detach of `entry = get_entry(i)` was
# rejected because entry_matches? compares the Tuple key element-wise
# (`index_get` on the interior `@key` field) and the stack-safety walk treated
# every IndexGet as an escape. S2 lost
# `@block_proc_capture_writebacks.delete({name, id})` results, so captured
# cells were never written back (S3 lower_method null return_type).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_tuple_key_delete_value_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

status=0
check() {
  local case_name="$1" expected="$2"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
      "$WORK_DIR/$case_name.cr" -o "$WORK_DIR/$case_name" >"$WORK_DIR/$case_name.build.log" 2>&1; then
    echo "FAIL[$case_name]: compile failed" >&2
    tail -20 "$WORK_DIR/$case_name.build.log" >&2
    status=1
    return
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$case_name" 5 512 >"$WORK_DIR/$case_name.run.log" 2>&1 || true
  printf '%s\n' "$expected" >"$WORK_DIR/$case_name.expected"
  sed -n '/^=== STDERR ===$/,/^===/p' "$WORK_DIR/$case_name.run.log" | grep -v '^===' | grep -v '^\[' >"$WORK_DIR/$case_name.actual" || true
  if ! diff -u "$WORK_DIR/$case_name.expected" "$WORK_DIR/$case_name.actual" >&2; then
    echo "FAIL[$case_name]" >&2
    status=1
  fi
}

cat >"$WORK_DIR/t1.cr" <<'CR'
h = {} of {String, UInt32} => Int32
n = ARGV.size > 5 ? "x" : "Lw"
h[{n, 30_u32}] = 5
f = h.delete({n, 30_u32})
STDERR.puts "del=#{f ? f : "nil"} size=#{h.size}"
h[{n, 1_u32}] = 10
old = h.put({n, 1_u32}, 20) { -1 }
STDERR.puts "put=#{old} now=#{h[{n, 1_u32}]}"
ha = {} of {String, UInt32} => Array(Int32)
ha[{"a", 7_u32}] = [1, 2, 3]
ra = ha.delete({"a", 7_u32})
STDERR.puts "arr=#{ra ? ra.size : "nil"}"
hn = {} of {String, {Int32, Int32}} => String
hn[{"k", {1, 2}}] = "v"
rn = hn.delete({"k", {1, 2}})
STDERR.puts "nested=#{rn ? rn : "nil"}"
hl = {} of {Int32, Int32} => Int32
10.times { |i| hl[{i, i}] = i * 2 }
pairs = hl.to_a
STDERR.puts "first=#{pairs.first[1]} last=#{pairs.last[1]}"
sum = 0
10.times { |i| v = hl.delete({i, i}); sum += v if v }
STDERR.puts "sum=#{sum} size=#{hl.size}"
STDERR.flush
CR
check t1 'del=5 size=0
put=10 now=20
arr=3
nested=v
first=0 last=18
sum=90 size=0'

if [ "$status" -ne 0 ]; then
  echo "FAIL: Tuple-key Hash#delete/#put lost the old entry value" >&2
  exit 1
fi
echo "PASS: Tuple-key Hash#delete/#put return the old entry value"
