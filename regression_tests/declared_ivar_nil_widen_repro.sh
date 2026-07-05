#!/usr/bin/env bash
# Oracle for assignment-driven union widening of explicitly declared ivars
# (s2_v12 frontier: STUB reparse_expr_for_macro with Nil-widened arena arg).
#
# Shape: an ivar with an explicit declared type (`property arena : ArenaLike`,
# alias union restriction) receives an assignment whose STATIC type stage1
# computes as nilable. lower_assign's ivar union-widening then silently
# replaced the declared type with `Nil | ArenaLike` in class_info (same-size
# unions), so every later `@arena` read demanded Nil-widened specializations
# of callees whose restriction is the bare alias -> no matching body -> the
# call lowered to a STUB abort.
#
# In the self-host build the poisoning RHS was a stage1 flow-narrowing
# imprecision inside a block-proc (fn=__crystal_block_proc_*, with_arena
# family) — valid Crystal that stage1 fails to narrow. This oracle triggers
# the same widening directly with an unguarded nilable assignment (original
# Crystal would reject it; our stage1 accepts it silently), which pins the
# containment property: a DECLARED ivar type is authoritative and must not
# be widened by assignment inference.
#
# RED (pre-fix): binary aborts with
#   STUB CALLED: Lowerer#reparse$$Int32_Nil|AstArena|PageArena|VirtualArena_PageArena
# GREEN: prints r=6, clean exit.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/declared_ivar_widen.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
cat > "$SRC" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

class AstArena
  def tag
    1
  end
end

class PageArena
  def tag
    2
  end
end

class VirtualArena
  def tag
    3
  end
end

alias ArenaLike = AstArena | PageArena | VirtualArena

class Lowerer
  property arena : ArenaLike

  def initialize(@arena : ArenaLike)
    @flag = true
  end

  def maybe_arena : ArenaLike?
    if @flag
      VirtualArena.new
    else
      nil
    end
  end

  # NOTE: is_a? chain instead of virtual .tag dispatch — the vdispatch table
  # for 3-variant all-reference unions is under-enumerated (separate
  # pre-existing family, see TODO), which would mask this oracle's signal.
  def reparse(x : Int32, source_arena : ArenaLike, target_arena : ArenaLike) : Int32
    s = source_arena.is_a?(VirtualArena) ? 3 : (source_arena.is_a?(PageArena) ? 2 : 1)
    t = target_arena.is_a?(VirtualArena) ? 3 : (target_arena.is_a?(PageArena) ? 2 : 1)
    x + s + t
  end

  def poison : Nil
    @arena = maybe_arena
  end

  def use(other : ArenaLike) : Int32
    reparse(1, @arena, other)
  end
end

l = Lowerer.new(AstArena.new)
l.poison
r = l.use(PageArena.new)
LibC.printf("r=%d\n", r)
CR

if ! "$COMPILER" "$SRC" --no-prelude -o "$OUT" > "$TMP_DIR/compile.log" 2>&1; then
  echo "FAIL: compile error" >&2
  tail -5 "$TMP_DIR/compile.log" >&2
  exit 1
fi

# Static check: the demanded reparse specialization must NOT be Nil-widened.
if nm "$OUT" 2>/dev/null | grep -q 'Hreparse\$\$Int32_Nil'; then
  echo "FAIL: Nil-widened reparse specialization demanded (declared ivar type was widened)" >&2
  exit 1
fi

RAW="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null)"
GOT="$(echo "$RAW" | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
EXPECTED='r=6'

if [[ "$GOT" != "$EXPECTED" ]]; then
  echo "FAIL: output mismatch" >&2
  echo "--- expected ---" >&2
  echo "$EXPECTED" >&2
  echo "--- got ---" >&2
  echo "$GOT" >&2
  echo "$RAW" | tail -3 >&2
  exit 1
fi
if ! echo "$RAW" | grep -q "\[EXIT: 0\]"; then
  echo "FAIL: non-zero exit (STUB abort?)" >&2
  echo "$RAW" | tail -2 >&2
  exit 1
fi
echo "PASS: declared ivar type survives nilable assignment (no Nil-widened demand)"
