#!/usr/bin/env bash
# Regression: included generic module restriction bound by the owner's
# instantiation. `struct Ptr(T); include Cmp(self)` with
# `module Cmp(T); def ==(other : T)` must reject a non-Ptr argument, so
# `Ptr(UInt64) == 3` (and Object#=== `self == other`) falls through to
# Value#== and returns false. The lazy `included_module_before_parent`
# lookup checked the module def with Cmp's T unbound (a wildcard), took
# Cmp#== for Int32/enum/class args, and the body then called a bodyless
# `Ptr(UInt64)#<=>$UInt64` (STUB, exit 134). Original-stdlib
# `Pointer(T) include Comparable(self)` reaches this through the
# Object#=== fan-out over `case stdio when Process::Redirect::Pipe`.
# Cases: owner param named T (collides with the module T) and U, enum /
# class / Int32 args through === and a direct ==, same-type Cmp#== (equal
# and unequal), and a call from a generic context whose own T differs.
# The `forall` free-var regression (FastFloat `"2.5".to_f`) is covered by
# type_receiver_class_method_def_repro.sh; no no-prelude reducer reaches
# the deferred lookup path.
# Each prints EXIT 7 (checked against the original compiler).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/included_module_restriction.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/owner_t_enum.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Object
  def ===(other)
    self == other
  end
end
struct Value
  def ==(other)
    false
  end
end
module Cmp(T)
  def ==(other : T)
    cmp = self <=> other
    cmp == 0
  end
end
struct Ptr(T)
  include Cmp(self)
  def initialize(@a : UInt64)
  end
  def addr : UInt64
    @a
  end
  def <=>(other : self) : Int32
    addr == other.addr ? 0 : 1
  end
end
enum Rd
  Pipe
  Inherit
  Close
end
p = Ptr(UInt64).new(5_u64)
LibC.exit((p === Rd::Pipe) ? 40 : 7)
CR

cat >"$WORK_DIR/owner_u_enum.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Object
  def ===(other)
    self == other
  end
end
struct Value
  def ==(other)
    false
  end
end
module Cmp(T)
  def ==(other : T)
    cmp = self <=> other
    cmp == 0
  end
end
struct Ptr(U)
  include Cmp(self)
  def initialize(@a : UInt64)
  end
  def addr : UInt64
    @a
  end
  def <=>(other : self) : Int32
    addr == other.addr ? 0 : 1
  end
end
enum Rd
  Pipe
  Inherit
  Close
end
p = Ptr(UInt64).new(5_u64)
LibC.exit((p === Rd::Pipe) ? 40 : 7)
CR

cat >"$WORK_DIR/owner_t_class.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Object
  def ===(other)
    self == other
  end
end
struct Value
  def ==(other)
    false
  end
end
module Cmp(T)
  def ==(other : T)
    cmp = self <=> other
    cmp == 0
  end
end
struct Ptr(T)
  include Cmp(self)
  def initialize(@a : UInt64)
  end
  def addr : UInt64
    @a
  end
  def <=>(other : self) : Int32
    addr == other.addr ? 0 : 1
  end
end
enum Rd
  Pipe
  Inherit
  Close
end
class Bx
end
p = Ptr(UInt64).new(5_u64)
LibC.exit((p === Bx.new) ? 40 : 7)
CR

cat >"$WORK_DIR/owner_t_int.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Object
  def ===(other)
    self == other
  end
end
struct Value
  def ==(other)
    false
  end
end
module Cmp(T)
  def ==(other : T)
    cmp = self <=> other
    cmp == 0
  end
end
struct Ptr(T)
  include Cmp(self)
  def initialize(@a : UInt64)
  end
  def addr : UInt64
    @a
  end
  def <=>(other : self) : Int32
    addr == other.addr ? 0 : 1
  end
end
enum Rd
  Pipe
  Inherit
  Close
end
p = Ptr(UInt64).new(5_u64)
LibC.exit((p === 3) ? 40 : 7)
CR

cat >"$WORK_DIR/direct_int.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Object
  def ===(other)
    self == other
  end
end
struct Value
  def ==(other)
    false
  end
end
module Cmp(T)
  def ==(other : T)
    cmp = self <=> other
    cmp == 0
  end
end
struct Ptr(T)
  include Cmp(self)
  def initialize(@a : UInt64)
  end
  def addr : UInt64
    @a
  end
  def <=>(other : self) : Int32
    addr == other.addr ? 0 : 1
  end
end
enum Rd
  Pipe
  Inherit
  Close
end
p = Ptr(UInt64).new(5_u64)
LibC.exit((p == 3) ? 40 : 7)
CR

cat >"$WORK_DIR/same_type_eq.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Object
  def ===(other)
    self == other
  end
end
struct Value
  def ==(other)
    false
  end
end
module Cmp(T)
  def ==(other : T)
    cmp = self <=> other
    cmp == 0
  end
end
struct Ptr(T)
  include Cmp(self)
  def initialize(@a : UInt64)
  end
  def addr : UInt64
    @a
  end
  def <=>(other : self) : Int32
    addr == other.addr ? 0 : 1
  end
end
enum Rd
  Pipe
  Inherit
  Close
end
p = Ptr(UInt64).new(5_u64)
q = Ptr(UInt64).new(5_u64)
LibC.exit((p === q) ? 7 : 40)
CR

cat >"$WORK_DIR/same_type_ne.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Object
  def ===(other)
    self == other
  end
end
struct Value
  def ==(other)
    false
  end
end
module Cmp(T)
  def ==(other : T)
    cmp = self <=> other
    cmp == 0
  end
end
struct Ptr(T)
  include Cmp(self)
  def initialize(@a : UInt64)
  end
  def addr : UInt64
    @a
  end
  def <=>(other : self) : Int32
    addr == other.addr ? 0 : 1
  end
end
enum Rd
  Pipe
  Inherit
  Close
end
p = Ptr(UInt64).new(5_u64)
q = Ptr(UInt64).new(6_u64)
LibC.exit((p === q) ? 40 : 7)
CR

cat >"$WORK_DIR/generic_ctx.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Object
  def ===(other)
    self == other
  end
end
struct Value
  def ==(other)
    false
  end
end
module Cmp(T)
  def ==(other : T)
    cmp = self <=> other
    cmp == 0
  end
end
struct Ptr(T)
  include Cmp(self)
  def initialize(@a : UInt64)
  end
  def addr : UInt64
    @a
  end
  def <=>(other : self) : Int32
    addr == other.addr ? 0 : 1
  end
end
enum Rd
  Pipe
  Inherit
  Close
end
struct Holder(T)
  def initialize(@v : T)
  end
  def mixed(p) : Int32
    (p === @v) ? 40 : 0
  end
  def same(p, q) : Int32
    (p == q) ? 7 : 50
  end
end
h = Holder(Int32).new(3)
p = Ptr(UInt64).new(5_u64)
q = Ptr(UInt64).new(5_u64)
LibC.exit(h.mixed(p) &+ h.same(p, q))
CR

for name in owner_t_enum owner_u_enum owner_t_class owner_t_int direct_int same_type_eq same_type_ne generic_ctx; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    echo "case $name: compile failed" >&2
    tail -20 "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 7\]' "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT 7):" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo included_module_restriction_lookup_repro_ok
