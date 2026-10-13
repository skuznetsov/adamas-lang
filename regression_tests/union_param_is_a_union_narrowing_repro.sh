#!/usr/bin/env bash
# Three HIR defects around union-typed values (stage2 root of Float32::MIN,
# MIN_EXP and computed constants evaluating to garbage/0 via MacroNumberValue's
# `initialize(value : Int32 | Int64 | Float32 | Float64)`):
#  (A) `union_value.is_a?(A | B)` compared the value's type id against the
#      check union's own type id (always false) instead of expanding per variant.
#  (B) `(Int64 | Float64).to_i64` unwrapped only the FIRST numeric variant, so a
#      Float64 payload was reinterpreted as Int64 bits (and vice versa).
#  (C) then-branch narrowing to a union target emitted a union->union Cast,
#      lowered by MIR to a Bitcast of a differently-shaped union.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_is_a_union.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_conv.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def pick(a : Int64, flag : Bool) : Int64 | Float64
  flag ? a + 4_i64 : 1.5
end

def pick3(k : Int32) : Int32 | Int64 | Float64
  return 2 if k == 0
  return 5_i64 if k == 1
  2.5
end

def pickn(k : Int32) : Int64 | Float64 | Nil
  return 9_i64 if k == 0
  return 4.75 if k == 1
  nil
end

def conv(v : Int64 | Float64) : Int64
  v.to_i64
end

def isf(v : Int64 | Float64) : Bool
  v.is_a?(Float64 | Float32)
end

def narrow(v : Int64 | Float64 | Nil) : Int64
  if v.is_a?(Int64 | Float64)
    v.to_i64
  else
    -1_i64
  end
end

r = 0
r |= 1 unless conv(pick(3_i64, true)) == 7_i64
r |= 2 unless conv(pick(3_i64, false)) == 1_i64
r |= 4 unless isf(pick(3_i64, false))
r |= 8 if isf(pick(3_i64, true))
r |= 16 unless pick3(0).to_f64 == 2.0 && pick3(1).to_f64 == 5.0 && pick3(2).to_f64 == 2.5
r |= 32 unless narrow(pickn(0)) == 9_i64 && narrow(pickn(1)) == 4_i64 && narrow(pickn(2)) == -1_i64
LibC.exit(r)
CR
cat >"$WORK_DIR/np_ctor.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Val
  getter value : Int64 | Float64

  def initialize(value : Int32)
    @value = value.to_i64
  end

  def initialize(value : Int64)
    @value = value
  end

  def initialize(value : Float32)
    @value = value.to_f64
  end

  def initialize(value : Float64)
    @value = value
  end

  def initialize(value : Int32 | Int64 | Float32 | Float64)
    @value = value.is_a?(Float32 | Float64) ? value.to_f64 : value.to_i64
  end
end

def pick(a : Int64, flag : Bool) : Int64 | Float64 | Nil
  flag ? a + 4_i64 : nil
end

def pickf(flag : Bool) : Int64 | Float64 | Nil
  flag ? -0.5 : nil
end

r = 0
if res = pick(3_i64, true)
  x = Val.new(res).value
  r |= 1 unless x.is_a?(Int64) && x == 7_i64
end
if res = pickf(true)
  x = Val.new(res).value
  r |= 2 unless x.is_a?(Float64) && x == -0.5
end
LibC.exit(r)
CR
for name in np_conv np_ctor; do
  flags=()
  [[ "$name" == np_* ]] && flags=(--no-prelude)
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
      "$WORK_DIR/$name.cr" ${flags[@]+"${flags[@]}"} -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1; then
    echo "case $name failed:" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo union_param_is_a_union_narrowing_repro_ok
