#!/usr/bin/env bash
# Regression: recursive-POD predicate must not mistake a REPEATED SIBLING field
# type for a cycle.
#
# `struct_type_is_recursive_pod_mir?` walks a struct's fields with a `seen` set.
# The bug: `seen` was an all-visited set that was never popped, so a struct with
# two sibling fields of the same POD type — e.g. `Pair{@a : Vec2, @b : Vec2}` —
# had `@a` add Vec2's id to `seen`, then `@b` hit the cycle guard and returned
# false. `Pair` was wrongly classified non_pod. The fix turns `seen` into a DFS
# ANCESTOR-PATH set (id removed on the way back up): a real cycle is a type
# reachable from itself along the path, not the same POD used twice as siblings.
#
# This predicate feeds the Stage 0++ per-type aggregation census, which prints
# `[BYVAL_TYPEAGG]   <tier> pod=<bool> <Type>: ...` under
# ADAMAS_STRUCT_BYVALUE_CENSUS=1. DoD assertions on those verdict lines:
#   Vec2        pod=true   (leaf POD)
#   Pair        pod=true   (two Vec2 siblings — the regression)
#   Quad        pod=true   (two Pair siblings — nested two levels deep)
#   WithString  pod=false  (String field -> ref-owning, must stay rejected)
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recursive_pod_nested.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/probe.cr"
cat >"$SRC" <<'CR'
struct Vec2
  @x : Int32
  @y : Int32
  def initialize(@x : Int32, @y : Int32); end
  def x : Int32; @x; end
end

struct Pair          # two POD siblings of the SAME type -> must be pod=true
  @a : Vec2
  @b : Vec2
  def initialize(@a : Vec2, @b : Vec2); end
end

struct Quad          # two Pair siblings -> nested-POD two levels deep, pod=true
  @p : Pair
  @q : Pair
  def initialize(@p : Pair, @q : Pair); end
end

struct WithString    # ref-owning field -> must stay pod=false
  @label : String
  @v : Vec2
  def initialize(@label : String, @v : Vec2); end
end

v = Vec2.new(1, 2)
p = Pair.new(Vec2.new(1, 2), Vec2.new(3, 4))
q = Quad.new(Pair.new(Vec2.new(1, 2), Vec2.new(3, 4)), Pair.new(Vec2.new(5, 6), Vec2.new(7, 8)))
ws = WithString.new("hi", Vec2.new(5, 6))
total = v.x + p.a.x + q.p.a.x + ws.v.x
STDERR.puts "total=#{total}"
STDERR.flush
CR

LOG="$TMP_DIR/census.log"
ADAMAS_STRUCT_BYVALUE_CENSUS=1 "$COMPILER" --emit mir "$SRC" -o "$TMP_DIR/probe" >/dev/null 2>"$LOG" || {
  echo "COMPILE_FAIL"; tail -20 "$LOG"; exit 1; }

# extract the pod=<bool> verdict for a given type from its [BYVAL_TYPEAGG] line
pod_for() {
  local type="$1"
  # match "[BYVAL_TYPEAGG]   <tier> pod=<bool> <Type>:"
  grep -E "\[BYVAL_TYPEAGG\].* ${type}:" "$LOG" | grep -oE 'pod=(true|false)' | head -1 | cut -d= -f2
}

fail=0
check() {
  local type="$1" want="$2"
  local got; got="$(pod_for "$type")"
  if [[ -z "$got" ]]; then
    echo "FAIL: no [BYVAL_TYPEAGG] verdict for $type"; fail=1; return
  fi
  echo "$type pod=$got (expect $want)"
  if [[ "$got" != "$want" ]]; then echo "FAIL: $type expected pod=$want got pod=$got"; fail=1; fi
}

check Vec2 true
check Pair true        # the regression: was false before the seen-backtrack fix
check Quad true        # nested two levels: sibling repeat at multiple depths
check WithString false # ref-owning field still correctly rejected

if [[ "$fail" -eq 0 ]]; then
  echo "recursive_pod_nested_sibling_ok"
  exit 0
else
  echo "recursive_pod_nested_sibling FAILED"
  exit 1
fi
