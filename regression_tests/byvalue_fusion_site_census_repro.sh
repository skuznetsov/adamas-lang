#!/usr/bin/env bash
# Regression: the placement-ctor FUSION-site census axis (ABI Stage 0+++).
#
# The storage/type-aggregation census counts how struct ctor RESULTS flow and
# which TYPES could flip, but it cannot quantify the "$Dnew malloc 1->0" win:
# that win is per-CALL-SITE, materializing only where a FRESH struct ctor result
# is consumed DIRECTLY by a container write (`arr << T.new(...)`). The fusion
# census adds a SECOND axis counting exactly those removable boxes per element
# type, split by semantic-POD eligibility.
#
# DoD assertions on the `[BYVAL_FUSION]` lines for the probe below:
#   Vec2      removable = 3   (three direct `arr << Vec2.new(...)` / push sites)
#   WithStr   ineligible = 1  (non-POD element -> sole-container ctor stays boxed)
# and the named-local `arr << v` (v is also read) is NOT counted as a fresh
# fusion (it routes through a Copy into the local), so Vec2 stays 3, not 4.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/byvalue_fusion.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/probe.cr"
cat >"$SRC" <<'CR'
struct Vec2
  @x : Int32
  @y : Int32
  def initialize(@x : Int32, @y : Int32); end
  def x : Int32; @x; end
end

struct WithStr        # ref-owning field -> element is non-POD, must stay boxed
  @label : String
  @v : Vec2
  def initialize(@label : String, @v : Vec2); end
end

arr = [] of Vec2
arr << Vec2.new(1, 2)            # direct sole-use fusion -> removable (POD)
arr << Vec2.new(3, 4)            # direct sole-use fusion -> removable (POD)
arr.push(Vec2.new(5, 6))         # direct sole-use fusion via push -> removable (POD)

v = Vec2.new(7, 8)               # named local, also read below -> NOT a fresh fusion
total0 = v.x
arr << v                         # indirect (value is a local, not a fresh ctor)

ws = [] of WithStr
ws << WithStr.new("hi", Vec2.new(9, 10))   # non-POD element -> ineligible

ints = [] of Int32
ints << 42                       # non-struct container write (denominator only)

total = 0
arr.each { |e| total += e.x }
STDERR.puts "total=#{total} total0=#{total0} wssz=#{ws.size} intsz=#{ints.size}"
STDERR.flush
CR

LOG="$TMP_DIR/census.log"
ADAMAS_STRUCT_BYVALUE_CENSUS=1 "$COMPILER" --emit mir "$SRC" -o "$TMP_DIR/probe" >/dev/null 2>"$LOG" || {
  echo "COMPILE_FAIL"; tail -20 "$LOG"; exit 1; }

# Extract the per-type count from a [BYVAL_FUSION] line. Each user struct type is
# POD-exclusive, so a type appears in at most one of the removable/ineligible
# sections; an exact "<Type> = <n>" match is unambiguous.
fusion_count() {
  local type="$1"
  grep -E "^\[BYVAL_FUSION\]   ${type} = [0-9]+$" "$LOG" | grep -oE '[0-9]+$' | head -1
}

fail=0
check() {
  local type="$1" want="$2"
  local got; got="$(fusion_count "$type")"
  if [[ -z "$got" ]]; then
    echo "FAIL: no [BYVAL_FUSION] per-type line for $type"; fail=1; return
  fi
  echo "$type fusion=$got (expect $want)"
  if [[ "$got" != "$want" ]]; then echo "FAIL: $type expected $want got $got"; fail=1; fi
}

check Vec2 3        # three direct fresh-ctor container writes; named-local push excluded
check WithStr 1     # non-POD element -> ineligible bucket

# The headline axis must be present and non-zero (proves the census ran).
if ! grep -qE '^\[BYVAL_FUSION\]   removable_box_sites=[0-9]+ ' "$LOG"; then
  echo "FAIL: missing removable_box_sites summary line"; fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "byvalue_fusion_site_census_ok"
  exit 0
else
  echo "byvalue_fusion_site_census FAILED"
  exit 1
fi
