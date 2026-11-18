#!/usr/bin/env bash
# Regression: `x.class == T` compares the runtime class with T exactly.
#
# Two literals compared with `==` were folded by their static types. For a
# virtual receiver `a.class == Dog` compared Animal with Dog and was always
# false; for a union receiver the union-typed literal went through the
# nilable-union comparison and `m.class == Int32` read a payload. A runtime
# `.class` now emits an exact class check: the active union variant, or the
# object header without the subclasses that `is_a?` accepts.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/runtime-class-eq.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
class Animal; end
class Dog < Animal; end
class Cat < Animal; end

i = ARGV.size
pets = [Dog.new, Cat.new] of Animal
a = pets[i]
STDERR.puts (a.class == Dog)
STDERR.puts (a.class == Cat)
STDERR.puts (a.class == Animal)
STDERR.puts (a.class != Dog)
STDERR.puts (Dog == a.class)
m = i == 0 ? 5 : nil
STDERR.puts (m.class == Int32)
STDERR.puts (m.class == Nil)
n = i == 0 ? nil : 5
STDERR.puts (n.class == Nil)
p = i == 0 ? pets[1] : nil
STDERR.puts (p.class == Cat)
STDERR.puts (p.class == Animal)
b = [7, "s", :k][i + 1]
STDERR.puts (b.class == String)
STDERR.puts (m.class == Comparable)
x = 7
STDERR.puts (x.class == Int32)
STDERR.puts(a.class == Dog ? "dog" : "other")
CR

expected='true
false
false
false
true
true
false
true
true
false
true
false
true
dog'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|^\[CRASH' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/m_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: program did not compile" >&2
  strip < "$WORK_DIR/build.log" | grep -i error | head -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: runtime .class compares with a type literal exactly"
