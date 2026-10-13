#!/usr/bin/env bash
# `x == Tv.new` where the receiver's own `==` only accepts another type
# (`H#==(other : H)`) must dispatch to the ancestor catch-all
# (`Reference#==(other)` -> false). For a subclass receiver (`H2 < H`) the
# parent-class fallback in lookup_parent_method bound H's typed
# `==(other : H)` body to `H2#==$Tv` without checking that the suffix arg
# type is accepted (h2t printed true). Hash(String, Int32) and a Symbol
# receiver compared with Bool must also pick their ancestor catch-alls.
# (The value type is named `Tv`, not `T`: a user type named `T` collides
# with generic type params — separate bug.)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/binary_eq_ancestor_target_preserve_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
class H
  def ==(other : H)
    true
  end
end

class H2 < H
end

struct Tv
  def initialize(@v : Int32); end
end

x = H.new
STDERR.puts "ht=#{x == Tv.new(1)}"
STDERR.puts "hh=#{x == H.new}"
STDERR.puts "h2t=#{H2.new == Tv.new(2)}"
STDERR.puts "h2h=#{H2.new == H.new}"
y = {"a" => 1}
STDERR.puts "hasht=#{y == Tv.new(1)}"
STDERR.puts "hashh=#{y == {"a" => 1}}"
STDERR.puts "symbool=#{:a == true}"
STDERR.puts "symsym=#{:a == :a}"
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
ht=false
hh=true
h2t=false
h2h=true
hasht=false
hashh=true
symbool=false
symsym=true
OUT
grep -oE '^[a-z_0-9]+=(true|false)' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: typed ancestor == target was rebound to a bare receiver base" >&2
  exit 1
fi
# Runtime output alone does not discriminate the Hash/Symbol case: the bare
# `Symbol#==` / `Hash(...)#==` stub happens to return false too. The rebind
# must not leave an unsuffixed receiver-base `==` call.
mkdir -p "$WORK_DIR/ir"
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/ir/t" --emit llvm-ir >"$WORK_DIR/ir.log" 2>&1; then
  cat "$WORK_DIR/ir.log" >&2
  exit 1
fi
if [[ ! -f "$WORK_DIR/ir/t.ll" ]]; then
  echo "FAIL: no LLVM IR emitted" >&2
  exit 1
fi
if grep -nE 'call i1 @(Symbol|Hash\$L[^ ]*\$R)\$H\$EQ\(' "$WORK_DIR/ir/t.ll" >&2; then
  echo "FAIL: ancestor == target rebound to an unsuffixed receiver base" >&2
  exit 1
fi
echo "PASS: typed ancestor == target preserved"
