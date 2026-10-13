#!/usr/bin/env bash
# Regression: a detached Hash::Entry copy (inline-container borrow snapshot)
# lives in a per-function stack slot. `entry.value` with a struct-typed V is an
# interior address into that slot; storing it into a tuple/array (Hash#to_a)
# made every element alias the last entry. The detach must only fire when the
# interior field reads stay local too.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_entry_detach_interior_borrow_repro.XXXXXX")"
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
record PT, name : String, args : Array(Int32), hb : Bool
h = {} of String => PT
h["a"] = PT.new("a", [1], false)
h["b"] = PT.new("b", [1, 2], true)
arr = h.to_a
arr.each do |k, t|
  STDERR.puts "#{k} #{t.name} #{t.args.size} #{t.hb}"
end
v = h["a"]
STDERR.puts v.name
STDERR.flush
CR
check c1 'a a 1 false
b b 2 true
a'

cat >"$WORK_DIR/c2.cr" <<'CR'
record PT, name : String, owner : String, args : Array(Int32), hs : Bool

class Holder
  def initialize
    @h = {} of String => PT
  end

  def add(n : String)
    @h[n] = PT.new(n, "Own", [1, 2], true)
  end

  def avail?(t : PT) : Bool
    STDERR.puts "#{t.owner} #{t.name} #{t.args.size} #{t.hs}"
    false
  end

  def retry : Int32
    n = 0
    @h.to_a.each do |name, target|
      next @h.delete(name) if avail?(target) && name == "zz"
      n += 1
    end
    n
  end
end

h = Holder.new
h.add("a")
h.add("b")
STDERR.puts h.retry
STDERR.flush
CR
check c2 'Own a 2 true
Own b 2 true
2'

if [ "$status" -ne 0 ]; then
  echo "FAIL: detached Hash::Entry struct value escaped its stack slot" >&2
  exit 1
fi
echo "PASS: Hash#to_a struct values own their entries"
