#!/usr/bin/env bash
# Oracle for vdispatch variant under-enumeration on all-reference unions via an
# INDEXED (arg-typed) call — the `arena[expr_id]` shape that crashes the
# produced stage2 self-build (s2_v13: infer_ivars_from_expr -> node_for_expr ->
# arena[expr_id] reads garbage / hits `unreachable`).
#
# Sibling of union_vdispatch_variant_enum_repro.sh. That oracle covers a 0-arg
# method call (`a.tag`); this one covers an arg-typed index call (`a[i]`), whose
# pending function name carries an arg suffix (`Owner#[]$Int32`). The RTA
# owner-gate keys on the suffixed method part, so recording union variants only
# under the bare part is not enough — the bare-part fallback in
# rta_method_part_matches_owner? closes that gap.
#
# RED (under-enum): t0=101 but t1/t2 wrong (dispatch to the first variant).
# GREEN (fixed):    t0=101 t1=202 t2=303, clean exit.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vdispatch_idx.XXXXXX")"
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
  def [](i : Int32) : Int32
    100 + i
  end
end

class PageArena
  def [](i : Int32) : Int32
    200 + i
  end
end

class VirtualArena
  def [](i : Int32) : Int32
    300 + i
  end
end

alias ArenaLike = AstArena | PageArena | VirtualArena

def pick(f : Int32) : ArenaLike
  if f == 0
    AstArena.new
  elsif f == 1
    PageArena.new
  else
    VirtualArena.new
  end
end

def probe(a : ArenaLike, i : Int32) : Int32
  a[i]
end

LibC.printf("t0=%d t1=%d t2=%d\n", probe(pick(0), 1), probe(pick(1), 2), probe(pick(2), 3))
CR

if ! "$COMPILER" "$SRC" --no-prelude -o "$OUT" > "$TMP_DIR/compile.log" 2>&1; then
  echo "FAIL: compile error"
  cat "$TMP_DIR/compile.log"
  exit 1
fi

GOT="$("$OUT" 2>/dev/null)"
EXPECT="t0=101 t1=202 t2=303"
if [[ "$GOT" == "$EXPECT" ]]; then
  echo "PASS: all union variants reachable through indexed vdispatch"
  exit 0
else
  echo "FAIL: indexed dispatch under-enumeration (expected '$EXPECT', got '$GOT')"
  exit 1
fi
