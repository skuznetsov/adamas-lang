#!/usr/bin/env bash
# Regression: a mixed array literal merges its element types like Crystal's
# `type_combine` (semantic/type_merge.cr).
#
# lower_array_literal collapsed mixed element types into their common
# ancestor class, so `[1, nil]` became `Array(Value)`, `[S1.new, S2.new]`
# became `Array(Struct)` and `[P.new, Q.new]` became `Array(Reference)`.
# Calls on those elements then failed ("case branch lost its owned Block
# scope", bodyless `Value#to_s`). Crystal merges two element types into
# their ancestor only when that ancestor can be a virtual root (never
# Object, Reference, Value, Struct, Number, Int, Float); otherwise the
# element type is the union. typeof() inference of a literal used only the
# first element (`typeof([1, "a"])` was `Array(Int32)`); it now uses the
# same merge. `[Dog.new, Cat.new]` -> `Array(Animal)` is the control for the
# virtual-root merge that must survive.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mixed-array-literal.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
class Animal; def name; "animal"; end; end
class Dog < Animal; def name; "dog"; end; end
class Cat < Animal; def name; "cat"; end; end
class P; def v; 10; end; end
class Q; def v; 20; end; end
struct S1; def v; 1; end; end
struct S2; def v; 2; end; end
a = [1, nil, 3]
STDERR.puts a.map { |v| v.nil? ? 0 : v + 10 }.inspect
b = [1, nil].first
STDERR.puts b.inspect
STDERR.puts b.nil?
c = [1, 2_i64, 3]
STDERR.puts c.sum(0_i64)
d = [Dog.new, Cat.new, nil]
STDERR.puts d.map { |x| x ? x.name : "none" }.join(",")
STDERR.puts [Dog.new, Cat.new].map(&.name).join(",")
STDERR.puts [P.new, Q.new].map(&.v).sum
STDERR.puts [S1.new, S2.new].map(&.v).sum
STDERR.puts typeof([1, nil]) == Array(Int32 | Nil)
STDERR.puts typeof(a) == Array(Int32?)
STDERR.puts typeof([1, "a"]) == Array(Int32 | String)
STDERR.puts typeof([Dog.new, Cat.new]) == Array(Animal)
CR

expected='[11, 0, 13]
1
false
6
dog,cat,none
dog,cat
30
3
true
true
true
true'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/m_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: mixed array literal program did not compile" >&2
  strip < "$WORK_DIR/build.log" | tail -5 >&2
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
echo "PASS mixed_array_literal_element_union"
