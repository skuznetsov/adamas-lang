#!/usr/bin/env bash
# Regression: the ContainerElemRepr classification SCAFFOLD (ABI storage slice).
#
# The scaffold adds a registry-backed three-way classifier
#   PointerSlot | InlineAddress | InlineValueCopy
# computed + logged under ADAMAS_INLINE_POD_CONTAINERS but NOT yet read by any
# lowering site (container_elem_storage_size_u64 / emit_array_get / _set /
# Pointer(T)#<< / unsafe_fetch are untouched). This reducer pins the
# classification AND proves the gate is diagnostic-only:
#
#   gate ON  -> [ELEM_REPR] lines emitted; expected labels:
#       Vec2 (8B leaf POD)            => InlineValueCopy
#       Vec3 (12B leaf POD)           => InlineValueCopy   (>8 sizing path)
#       Pair{Vec2,Vec2} (nested)      => PointerSlot        (carrier field)
#       WithStr (String field)        => PointerSlot        (ref-owning)
#       Slice( / StaticArray( /
#         Hash::Entry( families       => InlineAddress      (current behavior)
#       any Union element             => NOT InlineValueCopy (fallback)
#   gate OFF -> NO [ELEM_REPR] lines (byte-identical, diagnostic suppressed).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/elem_repr_scaffold.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/probe.cr"
cat >"$SRC" <<'CR'
struct Vec2
  @x : Int32
  @y : Int32
  def initialize(@x : Int32, @y : Int32); end
end

struct Vec3                       # 12 bytes (3 x Int32) leaf POD -> InlineValueCopy
  @x : Int32
  @y : Int32
  @z : Int32
  def initialize(@x : Int32, @y : Int32, @z : Int32); end
end

struct Pair                       # nested-carrier fields -> NOT leaf-storage-POD
  @a : Vec2
  @b : Vec2
  def initialize(@a : Vec2, @b : Vec2); end
end

struct WithStr                    # ref-owning field -> NOT POD
  @label : String
  @v : Vec2
  def initialize(@label : String, @v : Vec2); end
end

av = [] of Vec2
av << Vec2.new(1, 2)
a3 = [] of Vec3
a3 << Vec3.new(1, 2, 3)
ap = [] of Pair
ap << Pair.new(Vec2.new(1, 2), Vec2.new(3, 4))
aw = [] of WithStr
aw << WithStr.new("hi", Vec2.new(5, 6))

sl = Slice(Int32).new(4, 0)       # inline-container family -> InlineAddress
sa = uninitialized Int32[3]       # StaticArray( family    -> InlineAddress
h = {} of Int32 => Int32          # Hash::Entry( family     -> InlineAddress
h[1] = 2

au = [] of (Vec2 | Nil)           # union element -> NOT InlineValueCopy
au << Vec2.new(7, 8)
au << nil

STDERR.puts "ok av=#{av.size} a3=#{a3.size} ap=#{ap.size} aw=#{aw.size} sl=#{sl.size} sa=#{sa.size} h=#{h.size} au=#{au.size}"
STDERR.flush
CR

LOG_ON="$TMP_DIR/on.log"
LOG_OFF="$TMP_DIR/off.log"

ADAMAS_INLINE_POD_CONTAINERS=1 "$COMPILER" --emit mir "$SRC" -o "$TMP_DIR/probe_on" >/dev/null 2>"$LOG_ON" || {
  echo "COMPILE_FAIL (gate ON)"; tail -20 "$LOG_ON"; exit 1; }

"$COMPILER" --emit mir "$SRC" -o "$TMP_DIR/probe_off" >/dev/null 2>"$LOG_OFF" || {
  echo "COMPILE_FAIL (gate OFF)"; tail -20 "$LOG_OFF"; exit 1; }

fail=0

# Extract the repr label for an exact type name (== match before kind=).
repr_for() {
  local name="$1"
  grep -E "^\[ELEM_REPR\] ${name} kind=" "$LOG_ON" | grep -oE '=> [A-Za-z]+' | grep -oE '[A-Za-z]+$' | head -1
}

check() {
  local name="$1" want="$2"
  local got; got="$(repr_for "$name")"
  if [[ -z "$got" ]]; then
    echo "FAIL: no [ELEM_REPR] line for '$name'"; fail=1; return
  fi
  echo "$name => $got (expect $want)"
  if [[ "$got" != "$want" ]]; then echo "FAIL: $name expected $want got $got"; fail=1; fi
}

# Family lines carry a generic suffix; match by literal prefix (grep -F, the
# family name contains '(' which is an ERE metachar). The REAL family is a
# struct-kind type, so require kind=Struct (a union named `Slice(..) | ..` is
# NOT a family and must not be picked up here).
check_family_prefix() {
  local prefix="$1"
  local line; line="$(grep -F "[ELEM_REPR] ${prefix}" "$LOG_ON" | grep -F "kind=Struct" | head -1 || true)"
  if [[ -z "$line" ]]; then
    echo "FAIL: no struct-kind [ELEM_REPR] line for family '$prefix'"; fail=1; return
  fi
  echo "$line"
  if ! grep -q "=> InlineAddress" <<<"$line"; then
    echo "FAIL: family '$prefix' not InlineAddress"; fail=1
  fi
}

check Vec2 InlineValueCopy
check Vec3 InlineValueCopy
check Pair PointerSlot
check WithStr PointerSlot

check_family_prefix "Slice("
check_family_prefix "StaticArray("
check_family_prefix "Hash::Entry("

# Union elements must be PointerSlot (the fallback) — neither InlineValueCopy nor
# InlineAddress. The InlineAddress guard catches the family-name-on-union bug (a
# union named `Slice(..) | Slice(UInt8)` must NOT inherit the Slice family repr).
# Must have >=1 union line or the test is vacuous.
union_lines="$(grep -E '^\[ELEM_REPR\] .* kind=Union ' "$LOG_ON" || true)"
if [[ -z "$union_lines" ]]; then
  echo "FAIL: no union [ELEM_REPR] line found (test would be vacuous)"; fail=1
else
  bad_union="$(grep -E '=> (InlineValueCopy|InlineAddress)' <<<"$union_lines" || true)"
  if [[ -n "$bad_union" ]]; then
    echo "FAIL: union element(s) not classified PointerSlot:"; echo "$bad_union"; fail=1
  else
    echo "union elements: all PointerSlot (ok), count=$(grep -c '' <<<"$union_lines")"
  fi
fi

# Gate OFF must emit NO [ELEM_REPR] lines (diagnostic-only gate).
if grep -q '^\[ELEM_REPR\]' "$LOG_OFF"; then
  echo "FAIL: gate OFF still emitted [ELEM_REPR] lines (not diagnostic-only)"; fail=1
else
  echo "gate OFF: no [ELEM_REPR] lines (ok)"
fi

if [[ "$fail" -eq 0 ]]; then
  echo "container_elem_repr_scaffold_ok"
  exit 0
else
  echo "container_elem_repr_scaffold FAILED"
  exit 1
fi
