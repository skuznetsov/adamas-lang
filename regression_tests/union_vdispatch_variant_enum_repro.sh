#!/usr/bin/env bash
# Oracle for vdispatch variant under-enumeration on all-reference unions
# (PRE-EXISTING family, found 2026-07-05 while closing the s2_v12
# declared-ivar Nil-widening frontier; RED as of discovery).
#
# Shape: a 3-variant all-reference union alias; a method name shared by all
# variants dispatched through __vdispatch__*. The generated dispatcher's
# switch enumerates only a SUBSET of variants (observed: only AstArena for a
# fresh 3-variant union; only Ast+Page when demanded through other paths).
# Receivers of the missing variants hit the `unreachable` default — in
# practice LLVM folds this into an arbitrary branch, so calls silently
# dispatch to the WRONG variant method (t1/t2 print 1 instead of 2/3).
# Same family as the "hardcoded select-0/1 tid" vdispatch sibling.
#
# RED (current): t0=1 t1=1 t2=1
# GREEN (fixed): t0=1 t1=2 t2=3, clean exit.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vdispatch_enum.XXXXXX")"
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

def pick(f : Int32) : ArenaLike
  if f == 0
    AstArena.new
  elsif f == 1
    PageArena.new
  else
    VirtualArena.new
  end
end

def probe(a : ArenaLike) : Int32
  a.tag
end

LibC.printf("t0=%d t1=%d t2=%d\n", probe(pick(0)), probe(pick(1)), probe(pick(2)))
CR

if ! "$COMPILER" "$SRC" --no-prelude -o "$OUT" > "$TMP_DIR/compile.log" 2>&1; then
  echo "FAIL: compile error" >&2
  tail -5 "$TMP_DIR/compile.log" >&2
  exit 1
fi

RAW="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null)"
GOT="$(echo "$RAW" | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
EXPECTED='t0=1 t1=2 t2=3'

if [[ "$GOT" != "$EXPECTED" ]]; then
  echo "FAIL: dispatch under-enumeration (expected '$EXPECTED', got '$GOT')" >&2
  exit 1
fi
echo "PASS: all union variants reachable through vdispatch"
