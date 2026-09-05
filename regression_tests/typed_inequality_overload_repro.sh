#!/usr/bin/env bash
# Typed equality overloads reached through inherited inequality must preserve
# concrete, cross-class, and true Object behavior. The original failing signal
# is an ambiguous unsuffixed MIR target, not a runtime assertion mismatch.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_typed_inequality.XXXXXX")" || exit 2
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

cat > "$TMP_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Object
  def ==(other) : Bool
    false
  end

  def !=(other) : Bool
    !(self == other)
  end
end

class Reference < Object
end

class Plain < Reference
end

class AstArena < Reference
  def ==(other : AstArena) : Bool
    true
  end
end

class PageArena < Reference
  def ==(other : PageArena) : Bool
    false
  end
end

class VirtualArena < Reference
  def ==(other : VirtualArena) : Bool
    true
  end
end

alias ArenaLike = AstArena | PageArena | VirtualArena

def object_control(left : Object, right : Object) : Bool
  left != right
end

def concrete_arena(left : AstArena, right : AstArena) : Bool
  left != right
end

def union_neq(left : ArenaLike, right : ArenaLike) : Bool
  left != right
end

def run_probe : Int32
  object_result = object_control(Plain.new, Plain.new)
  arena_result = concrete_arena(AstArena.new, AstArena.new)
  union_aa = union_neq(AstArena.new, AstArena.new)
  union_ap = union_neq(AstArena.new, PageArena.new)
  union_pp = union_neq(PageArena.new, PageArena.new)
  union_vv = union_neq(VirtualArena.new, VirtualArena.new)

  # Expected: object=true, concrete_arena=false, union_aa=false,
  # union_ap=true, union_pp=true, union_vv=false. Keep this sparse call set:
  # adding all cross-class pairs can pre-materialize targets and mask the bug.
  if !object_result
    return 2
  end
  if arena_result
    return 4
  end
  if union_aa
    return 8
  end
  if !union_ap
    return 16
  end
  if !union_pp
    return 32
  end
  if union_vv
    return 64
  end
  0
end

LibC.exit(run_probe)
CR

"$SAFE_RUN" "$COMPILER" 30 1024 "$TMP_DIR/repro.cr" --no-prelude -o "$TMP_DIR/repro" > "$TMP_DIR/compile.log" 2>&1
compile_rc=$?
if [[ "$compile_rc" -ne 0 ]]; then
  cat "$TMP_DIR/compile.log"
  exit 1
fi
if [[ ! -x "$TMP_DIR/repro" ]]; then
  echo "FAIL: compiler produced no executable"
  exit 1
fi
"$SAFE_RUN" "$TMP_DIR/repro" 5 512 > "$TMP_DIR/runtime.log" 2>&1
runtime_rc=$?
if [[ "$runtime_rc" -ne 0 ]]; then
  cat "$TMP_DIR/runtime.log"
  exit 1
fi
echo "PASS: typed inequality overloads preserve runtime results"
