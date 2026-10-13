#!/usr/bin/env bash
# Annotation text keeps Crystal's `T[N]` sugar verbatim (`@b : UInt8[N]`,
# `def h(x : UInt8[9])`, `uninitialized UInt8[SZ]`). HIR never normalized it to
# `StaticArray(T, N)`, and a constant N was not resolved as a numeric type arg:
# the ivar/local got size 8 (pointer) or a STUB `h$$StaticArray...` was emitted.
# Stage2 hit this through Float::Printer buffers (`UInt8[BUFFER_SIZE]`).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/static_array_constant_size_sugar_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

status=0
check() {
  local case_name="$1" expected="$2"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
      "$WORK_DIR/$case_name.cr" --no-prelude -o "$WORK_DIR/$case_name" >"$WORK_DIR/$case_name.build.log" 2>&1; then
    echo "FAIL[$case_name]: compile failed" >&2
    tail -20 "$WORK_DIR/$case_name.build.log" >&2
    status=1
    return
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$case_name" 5 512 >"$WORK_DIR/$case_name.run.log" 2>&1 || true
  printf '%s\n' "$expected" >"$WORK_DIR/$case_name.expected"
  sed -n '/^=== STDOUT ===$/,/^===/p' "$WORK_DIR/$case_name.run.log" | grep -v '^===' | grep -v '^\[' >"$WORK_DIR/$case_name.actual" || true
  if ! diff -u "$WORK_DIR/$case_name.expected" "$WORK_DIR/$case_name.actual" >&2; then
    echo "FAIL[$case_name]" >&2
    status=1
  fi
}

cat >"$WORK_DIR/c1.cr" <<'CR'
lib LibC
  fun printf(fmt : UInt8*, ...) : Int32
end
module M
  extend self
  SZ = 17
  def f
    str = uninitialized UInt8[SZ]
    LibC.printf("%d\n", sizeof(typeof(str)))
  end
end
SZ2 = 9
def g
  a = uninitialized UInt8[SZ2]
  LibC.printf("%d\n", sizeof(typeof(a)))
  b = uninitialized StaticArray(UInt8, SZ2)
  LibC.printf("%d\n", sizeof(typeof(b)))
end
class C
  N = 5
  @b = uninitialized UInt8[N]
  def s; sizeof(typeof(@b)); end
end
M.f
g
LibC.printf("%d\n", C.new.s)
CR
check c1 '17
9
9
5'

cat >"$WORK_DIR/c2.cr" <<'CR'
lib LibC
  fun printf(fmt : UInt8*, ...) : Int32
end
SZ2 = 9
class C
  N = 5
  @b = uninitialized UInt8[N]
  def s; sizeof(typeof(@b)); end
end
def g
  a = uninitialized StaticArray(UInt8, SZ2)
  LibC.printf("%d\n", sizeof(typeof(a)))
end
def h(x : UInt8[SZ2])
  LibC.printf("%d\n", sizeof(typeof(x)))
end
g
LibC.printf("%d\n", C.new.s)
b = uninitialized UInt8[9]
h(b)
CR
check c2 '9
5
9'

cat >"$WORK_DIR/c3.cr" <<'CR'
lib LibC
  fun printf(fmt : UInt8*, ...) : Int32
end
def g
  a = uninitialized StaticArray(UInt8, 9)
  LibC.printf("%d\n", sizeof(typeof(a)))
  b = uninitialized UInt8[9]
  LibC.printf("%d\n", sizeof(typeof(b)))
end
def h(x : UInt8[9])
  LibC.printf("%d\n", sizeof(typeof(x)))
end
g
b = uninitialized UInt8[9]
h(b)
CR
check c3 '9
9
9'

cat >"$WORK_DIR/c4.cr" <<'CR'
lib LibC
  fun printf(fmt : UInt8*, ...) : Int32
end
class C
  N = 5
  @b = uninitialized UInt8[5]
  @c = uninitialized UInt8[N]
  @d : UInt8[N]
  def initialize; @d = uninitialized UInt8[N]; end
  def s; sizeof(typeof(@b)); end
  def t; sizeof(typeof(@c)); end
  def u; sizeof(typeof(@d)); end
end
c = C.new
LibC.printf("%d %d %d\n", c.s, c.t, c.u)
CR
check c4 '5 5 5'

cat >"$WORK_DIR/c5.cr" <<'CR'
lib LibC
  fun printf(fmt : UInt8*, ...) : Int32
end
class C
  N = 5
  @d : UInt8[N]
  @e : StaticArray(UInt8, N)
  def initialize; @d = uninitialized UInt8[N]; @e = uninitialized StaticArray(UInt8, N); end
  def u; sizeof(typeof(@d)); end
  def v; sizeof(typeof(@e)); end
end
c = C.new
LibC.printf("%d %d\n", c.u, c.v)
CR
check c5 '5 5'

if [ "$status" -ne 0 ]; then
  echo "FAIL: T[N] / constant-N StaticArray annotation sized wrongly" >&2
  exit 1
fi
echo "PASS: T[N] sugar and constant-N StaticArray sizes resolve"
