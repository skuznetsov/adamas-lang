#!/usr/bin/env bash
# Mixed unions must use Crystal's MixedUnion layout (codegen/unions.cr): the
# payload is aligned to at least a pointer word, i.e. { i32, [N x i64] } with
# the payload at +8 (Int128 variants: +16). V2 used { i32, [N x i32] } with a
# 4-aligned payload, so pointer payloads sat at +4 where Boehm (8-byte scan)
# never sees them, and size/stride diverged from original Crystal. Checks
# (all match original Crystal): payload offset for ref/Int32/Int128 variants,
# union copy and widening, pointer stride 16, struct with union ivar = 24 B,
# and the String#index/byte_index Nil|Int32 fast paths that hand-build the
# union (they used to write the payload at +4).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_payload_word_layout.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun malloc(size : UInt64) : Void*
end

fun __crystal_malloc64(size : UInt64) : Void*
  LibC.malloc(size)
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

class Obj
  @v : Int32
  def initialize(@v)
  end
  def v
    @v
  end
end

struct S
  @a : Int32 | Nil
  @c : Int8
  def initialize(@a, @c)
  end
  def a
    @a
  end
end

def take(u : Int32 | Nil) : Int32 | Nil
  u
end

def pick_obj(f : Bool) : Obj | Int32
  f ? Obj.new(42) : 1
end

def wide(u : Int32 | Nil) : Int32 | Int64 | Nil
  u
end

r = 0
# 1: class-ref payload is an aligned word at +8
o = pick_obj(true)
po = pointerof(o).as(UInt64*)
r |= 1 unless (po + 1).as(Obj*).value.v == 42
# 2: union copy keeps payload at +8
x0 : Int32 | Nil = 13
x : Int32 | Nil = take(x0)
z : Int32 | Nil = x
pz = pointerof(z).as(Int32*)
r |= 2 unless (pz + 2).value == 13
# 4: union -> wider union coerce
w : Int32 | Int64 | Nil = wide(21.as(Int32 | Nil))
pw = pointerof(w).as(Int32*)
r |= 4 unless (pw + 2).value == 21 && w.is_a?(Int32)
# 8: stride of pointer-to-union
p = pointerof(x).as(Pointer(Int32 | Nil))
r |= 8 unless ((p + 1).address - p.address) == 16
# 16: struct with union ivar + trailing byte
r |= 16 unless sizeof(S) == 24
s = S.new(17, 1_i8)
sa = s.a
r |= 32 unless sa.is_a?(Int32) && sa == 17
# 64: by-value return read back through is_a?
r |= 64 unless (o.is_a?(Obj) && o.v == 42)
# 128: Int128 union is 16-aligned (payload at +16, size 32)
q = 5_i128.as(Int128 | Nil)
pq = pointerof(q).as(Int64*)
r |= 128 unless sizeof(Int128 | Nil) == 32 && (pq + 2).value == 5_i64
LibC.exit(r == 0 ? 3 : (r == 3 ? 255 : r))
CR
cat >"$WORK_DIR/sidx.cr" <<'CR'
s = ARGV.size > 5 ? "zzz" : "hello world"
a = s.index("wor")
b = s.index("xyz")
c = s.index('o')
d = s.byte_index('w'.ord.to_u8)
e = s.rindex('o')
STDERR.puts "a=#{a.inspect} b=#{b.inspect} c=#{c.inspect} d=#{d.inspect} e=#{e.inspect}"
ok = a == 6 && b.nil? && c == 4 && d == 6 && e == 7
exit(ok ? 3 : 1)
CR
run_case() {
  local name="$1"; shift
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" "$@" -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/$name.run.log"; then
    echo "$name: want EXIT 3" >&2
    cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
}
run_case np --no-prelude
run_case sidx
echo union_payload_word_layout_repro_ok
