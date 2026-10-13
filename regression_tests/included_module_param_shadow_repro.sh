#!/usr/bin/env bash
# Regression: an included generic module whose declared param collides with
# (or is shadowed by) the including type's params, e.g.
#   module Cmp(T); def probe(other : T); ...; end; end
#   struct Pt(T); include Cmp(self); end
# Inside the module body T must be Cmp's T (= Pt(UInt64)), not Pt's T
# (= UInt64). Two roots: store_function_type_param_map let the owner's T
# beat the module's T, and lazy lowering merged the receiver's pending map
# (Pt's params plus synthesized T/K/K2 aliases) over the registered module
# map. Original-stdlib `include Comparable(self)` in generic structs hits
# this ("receiver repair left bodyless target Pt(UInt64)#<=>$UInt64").
# The last case checks that an owner method still sees the owner's T.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/included_module_param.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/owner_t_collides.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
module Cmp(T)
  def probe(other : T) : Int32
    which(other)
  end
  def tprobe : Int32
    T.code
  end
end
struct UInt64
  def self.code : Int32
    20
  end
end
struct Pt(T)
  include Cmp(self)
  def initialize(@v : Int32)
  end
  def self.code : Int32
    30
  end
  def which(x : UInt64) : Int32
    2
  end
  def which(x : Pt(UInt64)) : Int32
    3
  end
end
pa = Pt(UInt64).new(3)
LibC.exit(pa.probe(pa) + pa.tprobe)
CR
cat >"$WORK_DIR/owner_u.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
module Cmp(T)
  def probe(other : T) : Int32
    which(other)
  end
  def tprobe : Int32
    T.code
  end
end
struct UInt64
  def self.code : Int32
    20
  end
end
struct Pt(U)
  include Cmp(self)
  def initialize(@v : Int32)
  end
  def self.code : Int32
    30
  end
  def which(x : UInt64) : Int32
    2
  end
  def which(x : Pt(UInt64)) : Int32
    3
  end
end
pa = Pt(UInt64).new(3)
LibC.exit(pa.probe(pa) + pa.tprobe)
CR
cat >"$WORK_DIR/include_generic_self.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
module Cmp(T)
  def probe(other : T) : Int32
    which(other)
  end
  def tprobe : Int32
    T.code
  end
end
struct UInt64
  def self.code : Int32
    20
  end
end
struct Pt(T)
  include Cmp(Pt(T))
  def initialize(@v : Int32)
  end
  def self.code : Int32
    30
  end
  def which(x : UInt64) : Int32
    2
  end
  def which(x : Pt(UInt64)) : Int32
    3
  end
end
pa = Pt(UInt64).new(3)
LibC.exit(pa.probe(pa) + pa.tprobe)
CR
cat >"$WORK_DIR/comparable_self.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
module Comparable(T)
  def ==(other : T)
    cmp = self <=> other
    cmp ? cmp == 0 : false
  end
end
struct Struct
  def ==(other) : Bool
    false
  end
end
struct Pt(T)
  include Comparable(self)
  def initialize(@v : Int32)
  end
  getter v : Int32
  def <=>(other : self)
    @v == other.v ? 0 : 1
  end
end
code = 0
pa = Pt(UInt64).new(3)
pb = Pt(UInt64).new(3)
code |= 1 if pa == pb

LibC.exit(code)
CR
cat >"$WORK_DIR/owner_method_keeps_owner_t.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
module Cmp(T)
  def probe(other : T) : Int32
    which(other)
  end
  def tprobe : Int32
    T.code
  end
end
struct UInt64
  def self.code : Int32
    20
  end
end
struct Pt(T)
  include Cmp(self)
  def initialize(@v : Int32)
  end
  def self.code : Int32
    30
  end
  def ownt : Int32
    T.code
  end
  def which(x : UInt64) : Int32
    2
  end
  def which(x : Pt(UInt64)) : Int32
    3
  end
end
pa = Pt(UInt64).new(3)
LibC.exit(pa.ownt + pa.tprobe)
CR
for spec in owner_t_collides:33 owner_u:33 include_generic_self:33 comparable_self:1 owner_method_keeps_owner_t:50; do
  name="${spec%%:*}"
  want="${spec##*:}"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    echo "case $name: compile failed" >&2
    tail -20 "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q "^\[EXIT: $want\]" "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT $want):" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo included_module_param_shadow_repro_ok
