#!/usr/bin/env bash
# Regression: `entry = get_entry(i)` bound a borrowed interior pointer into
# Hash @entries storage (InlineAddress). Hash#delete cleared / #put replaced
# the slot before returning `entry.value`, so delete returned nil/0 and put
# returned the NEW value. S2 lost `@yield_cont_next_locals.delete(...)`
# results, turning `next` targets into Unreachable (S3 trap).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_delete_value_repro.XXXXXX")"
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

cat >"$WORK_DIR/c1.cr" <<'CR'
h = {} of UInt32 => Int32
h[2_u32] = 5
r = h.delete(2_u32)
STDERR.puts "i=#{r ? r : "nil"} size=#{h.size}"
hs = {} of String => String
hs["a"] = "x"
rs = hs.delete("a")
STDERR.puts "s=#{rs ? rs : "nil"} size=#{hs.size}"
ha = {} of Int32 => Array(Int32)
ha[1] = [1, 2]
ra = ha.delete(1)
STDERR.puts "a=#{ra ? ra.size : "nil"} size=#{ha.size}"
rb = ha.delete(9) { [7] }
STDERR.puts "b=#{rb.size}"
ha[3] = [1, 2, 3]
rc = ha.delete(3) { [7] }
STDERR.puts "c=#{rc.size}"
STDERR.flush
CR
check c1 'i=5 size=0
s=x size=0
a=2 size=0
b=1
c=3'

cat >"$WORK_DIR/c2.cr" <<'CR'
h = {} of Int32 => Int32
h[1] = 10
old = h.put(1, 20) { 0 }
STDERR.puts "put=#{old} now=#{h[1]}"
hs = {} of String => String
hs["k"] = "a"
olds = hs.put("k", "b") { "none" }
STDERR.puts "puts=#{olds} now=#{hs["k"]}"
nw = hs.put("z", "c") { "none" }
STDERR.puts "new=#{nw}"
hc = {} of Int32 => Int32
10.times { |i| hc[i] = i * 2 }
sum = 0
10.times { |i| v = hc.delete(i); sum += v if v }
STDERR.puts "sum=#{sum} size=#{hc.size}"
STDERR.flush
CR
check c2 'put=10 now=20
puts=a now=b
new=none
sum=90 size=0'

if [ "$status" -ne 0 ]; then
  echo "FAIL: Hash#delete/#put lost the old entry value" >&2
  exit 1
fi
echo "PASS: Hash#delete/#put return the old entry value"
