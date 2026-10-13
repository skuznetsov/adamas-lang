#!/usr/bin/env bash
# Regression: a self-call such as `same?(other)` with a builtin-reserved arg
# type (String, Char, Symbol, ...) against overloads `same?(Reference)` /
# `same?(Nil)` lowered to the UNSUFFIXED `Reference#same?(String)`. The
# overload compatibility check only walked the ancestor chain for user types
# (get_type_descriptor is nil for builtin TypeRef ids), so `String < Reference`
# was never seen and no overload matched. MIR then resolved the bare name
# fuzzily; once the family had several members (stage2: $Nil, $Builder,
# $Reference) it became "Ambiguous MIR call target", and the binary hit a STUB.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/builtin_arg_ancestor_overload_suffix_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/bs.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class Reference
  def same?(other : Reference) : Bool
    object_id == other.object_id
  end
  def same?(other : Nil) : Bool
    false
  end
  def object_id : Int64
    1_i64
  end
end

class String < Reference
  def ==(other : self) : Bool
    return true if same?(other)
    false
  end
  def <=>(other : self) : Int32
    return 0 if same?(other)
    1
  end
end

a = String.new
code = 0
code |= 1 unless a.==(a)
code |= 2 unless a.<=>(a) == 0
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 4096 \
    "$WORK_DIR/bs.cr" --no-prelude --emit hir -o "$WORK_DIR/bs" >"$WORK_DIR/bs.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/bs.build.log" >&2
  exit 1
fi
if grep -q 'Reference#same?(' "$WORK_DIR/bs.hir"; then
  echo "FAIL: unsuffixed Reference#same?( call in HIR" >&2
  grep -n 'Reference#same?(' "$WORK_DIR/bs.hir" | head -5 >&2
  exit 1
fi
if ! grep -q 'Reference#same?\$Reference(' "$WORK_DIR/bs.hir"; then
  echo "FAIL: missing Reference#same?\$Reference call in HIR" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/bs" 5 512 >"$WORK_DIR/bs.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/bs.run.log"; then
  echo "FAIL: runtime result" >&2
  tail -10 "$WORK_DIR/bs.run.log" >&2
  exit 1
fi
echo "PASS"
