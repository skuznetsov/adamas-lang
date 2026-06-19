#!/usr/bin/env bash
# Regression: dead struct default-init malloc elimination (by-value ABI lever iii).
#
# Today every struct-typed ivar with no usable default emits, inside the
# allocator (T.new), a zero-filled struct Allocate + FieldSet *before* calling
# initialize (ast_to_hir.cr:29679 regular / :30200 overload). For
# `Particle{@pos,@vel : Vec2}` that is TWO `alloc gc Type#N, size=8` per
# Particle.new, each memcopy'd into a field and then immediately OVERWRITTEN by
# initialize's `@pos = pos` / `@vel = vel`. They are dead allocations.
#
# The gated optimization (ADAMAS_SKIP_DEAD_DEFAULT_INIT=1, default OFF) skips the
# zero-struct alloc for an ivar ONLY when initialize has a dominating,
# unconditional FieldSet to that ivar before ANY read/escape of self or that
# field. It MUST keep the alloc when initialize:
#   - reads the field before writing it          (read-before-write)
#   - lets self escape before the write           (self-escape-before-write)
#   - writes the field only on one branch         (branch-partial-write)
#
# DoD assertions (MIR via --emit mir, count `alloc gc Type#*, size=8` inside the
# relevant T.new function):
#   gate OFF: positive Particle.new has >=2 dead Vec2 allocs   (current baseline)
#   gate ON : positive Particle.new has 0 dead Vec2 allocs     (optimized)
#   gate ON : each negative still has >=1 dead Vec2 alloc       (correctly kept)
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dead_default_init.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

VEC2='struct Vec2
  @x : Int32
  @y : Int32
  def initialize(@x : Int32, @y : Int32)
  end
  def x : Int32
    @x
  end
end
'

# --- positive: initialize sets both fields unconditionally, first thing ---
POS="${VEC2}struct Particle
  @pos : Vec2
  @vel : Vec2
  def initialize(@pos : Vec2, @vel : Vec2)
  end
end
p = Particle.new(Vec2.new(1, 2), Vec2.new(3, 4))
STDERR.puts(p.pos.x)
"

# --- negative 1: read-before-write (uses @pos before assigning it) ---
NEG_READ="${VEC2}struct Holder
  @pos : Vec2
  def initialize(pos : Vec2)
    z = @pos.x          # reads the (zero) field BEFORE writing it
    @pos = pos
    STDERR.puts(z)
  end
end
h = Holder.new(Vec2.new(1, 2))
STDERR.puts(h.@pos.x)
"

# --- negative 2: self-escape-before-write (passes self out before assigning) ---
NEG_ESCAPE="${VEC2}def sink(h) : Int32
  0
end
struct Holder2
  @pos : Vec2
  def initialize(pos : Vec2)
    sink(self)          # self escapes BEFORE the field is written
    @pos = pos
  end
end
h = Holder2.new(Vec2.new(1, 2))
STDERR.puts(h.@pos.x)
"

# --- negative 3: branch-partial-write (field set on only one branch) ---
NEG_BRANCH="${VEC2}struct Holder3
  @pos : Vec2
  def initialize(pos : Vec2, flag : Bool)
    if flag
      @pos = pos        # conditional write -> NOT dominating
    end
  end
end
h = Holder3.new(Vec2.new(1, 2), true)
STDERR.puts(h.@pos.x)
"

# count `alloc gc Type#*, size=8` inside the named T.new function in MIR
count_dead_allocs() {
  local src="$1" newfn="$2" gate="$3"
  local cr="$TMP_DIR/r.cr" out="$TMP_DIR/r"
  printf '%s' "$src" >"$cr"
  if [[ "$gate" == "on" ]]; then
    ADAMAS_SKIP_DEAD_DEFAULT_INIT=1 "$COMPILER" --emit mir "$cr" -o "$out" >/dev/null 2>"$TMP_DIR/err" || {
      echo "COMPILE_FAIL gate=$gate fn=$newfn"; cat "$TMP_DIR/err"; exit 1; }
  else
    "$COMPILER" --emit mir "$cr" -o "$out" >/dev/null 2>"$TMP_DIR/err" || {
      echo "COMPILE_FAIL gate=$gate fn=$newfn"; cat "$TMP_DIR/err"; exit 1; }
  fi
  awk -v fn="func @${newfn}" '
    index($0, fn)==1 {f=1}
    f && /^}/ {exit}
    f && /alloc gc Type#[0-9]+, size=8/ {n++}
    END {print n+0}
  ' "$out.mir"
}

fail=0

base_pos="$(count_dead_allocs "$POS" "Particle.new\$Vec2_Vec2" off)"
echo "gate OFF: positive Particle.new dead Vec2 allocs = $base_pos (expect >=2)"
if [[ "$base_pos" -lt 2 ]]; then echo "FAIL: baseline did not show the dead allocs"; fail=1; fi

on_pos="$(count_dead_allocs "$POS" "Particle.new\$Vec2_Vec2" on)"
echo "gate ON : positive Particle.new dead Vec2 allocs = $on_pos (expect 0)"
if [[ "$on_pos" -ne 0 ]]; then echo "FAIL: positive not optimized under gate ON"; fail=1; fi

on_read="$(count_dead_allocs "$NEG_READ" "Holder.new\$Vec2" on)"
echo "gate ON : neg read-before-write Holder.new dead allocs = $on_read (expect >=1)"
if [[ "$on_read" -lt 1 ]]; then echo "FAIL: read-before-write wrongly optimized"; fail=1; fi

on_escape="$(count_dead_allocs "$NEG_ESCAPE" "Holder2.new\$Vec2" on)"
echo "gate ON : neg self-escape Holder2.new dead allocs = $on_escape (expect >=1)"
if [[ "$on_escape" -lt 1 ]]; then echo "FAIL: self-escape-before-write wrongly optimized"; fail=1; fi

on_branch="$(count_dead_allocs "$NEG_BRANCH" "Holder3.new\$Vec2_Bool" on)"
echo "gate ON : neg branch-partial Holder3.new dead allocs = $on_branch (expect >=1)"
if [[ "$on_branch" -lt 1 ]]; then echo "FAIL: branch-partial-write wrongly optimized"; fail=1; fi

if [[ "$fail" -eq 0 ]]; then
  echo "dead_default_init_elim_ok"
  exit 0
else
  echo "dead_default_init_elim FAILED"
  exit 1
fi
