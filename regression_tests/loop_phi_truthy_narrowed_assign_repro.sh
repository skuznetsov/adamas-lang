#!/usr/bin/env bash
# Loop-phi widening inferred `cv = r` inside `if r` from r's declared
# `Int64 | Nil` type, ignoring the truthy narrowing of the enclosing branch.
# The phi for cv became a Nil|Int64 union and `cv &+= 1` was called on the
# union without unwrap, yielding garbage (0). In the compiler this broke enum
# member numbering (register_enum: `if resolved; current_value = resolved`),
# so `Frontend::NodeKind` values collapsed to 0 in S2. w4: `cv = r.not_nil!`
# was inferred as Object (no local dataflow through not_nil!).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loop_phi_truthy_narrowed_assign_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
def w1(n : Int32) : Int64
  cv = 0_i64
  i = 0
  while i < n
    r = i == 2 ? 5_i64 : nil
    if r
      cv = r
    else
      cv &+= 1
    end
    STDERR.puts "w1 #{cv}"
    i += 1
  end
  cv
end

def w2(n : Int32) : Int64
  cv = 0_i64
  i = 0
  while i < n
    r = i == 1 ? 7_i64 : nil
    unless r
      cv &+= 2
    else
      cv = r
    end
    STDERR.puts "w2 #{cv}"
    i += 1
  end
  cv
end

def w3(vals : Array(Int32?)) : Int64
  cv = 0_i64
  vals.each do |v|
    got : Int64? = nil
    if x = v
      got = x.to_i64
    end
    if got
      cv = got
    else
      cv &+= 1
    end
    STDERR.puts "w3 #{cv}"
  end
  cv
end

def w4(n : Int32) : Int64
  cv = 0_i64
  i = 0
  while i < n
    r : Int64? = nil
    r = 5_i64 if i == 2
    if i == 3
      cv = r.not_nil! if r
    end
    if r
      cv = r.not_nil!
    else
      cv &+= 1
    end
    STDERR.puts "w4 #{cv}"
    i += 1
  end
  cv
end

w1(4)
w2(3)
a = [] of Int32?
a << nil
a << 5
a << nil
w3(a)
w4(4)
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
printf 'w1 1\nw1 2\nw1 5\nw1 6\nw2 2\nw2 7\nw2 9\nw3 1\nw3 5\nw3 6\nw4 1\nw4 2\nw4 5\nw4 6\n' >"$WORK_DIR/expected"
grep -E '^w[1234] ' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: loop-phi assignment ignored truthy branch narrowing" >&2
  exit 1
fi
echo "PASS: loop-phi assignment honors truthy branch narrowing"
