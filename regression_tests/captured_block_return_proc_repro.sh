#!/usr/bin/env bash
# A captured block param that the callee only returns (never calls) was
# passed as a raw function pointer, so `def run_proc(&blk : Int32 -> Bool);
# blk; end` handed the caller a bare fnptr typed as Proc: `pr.call(5)` then
# read {fn, env} out of the code bytes and crashed. The return must
# materialize a real Proc, like an ivar store of the same param does.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/captured_block_return_proc_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
def run_proc(&blk : Int32 -> Bool)
  blk
end

def run_proc_ret(&blk : Int32 -> Bool)
  return blk
end

def run_and_call(&blk : Int32 -> Bool)
  blk.call(5)
end

a = 5
pr = run_proc { |x| x == a }
STDERR.puts "p1=#{pr.call(5)}"
STDERR.puts "p2=#{pr.call(6)}"
pr2 = run_proc_ret { |x| x > a }
STDERR.puts "r1=#{pr2.call(9)}"
STDERR.puts "r2=#{pr2.call(1)}"
STDERR.puts "c1=#{run_and_call { |x| x == a }}"
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
p1=true
p2=false
r1=true
r2=false
c1=true
OUT
grep -oE '^[a-z_0-9]+=(true|false)' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: returned captured block was not materialized as a Proc" >&2
  exit 1
fi
echo "PASS: returned captured block is a Proc"
