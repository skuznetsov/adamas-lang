#!/usr/bin/env bash
# A statically known `x.class` passed as a call argument was rewritten into
# the class-name String literal, so `p(C.new.class)` bound `object : String`
# and dispatched String#inspect(IO) (never demanded -> abort stub). A
# non-virtual `.class` must stay a type value and dispatch Class methods.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/static_dot_class_arg.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_dot_class.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun strlen(s : UInt8*) : UInt64
end

abstract class Sink
  abstract def put(s : String) : Nil
end

class Cnt < Sink
  @n = 0_u64

  def put(s : String) : Nil
    @n += LibC.strlen(s.to_unsafe)
  end

  def n
    @n
  end
end

class String
  def to_unsafe : UInt8*
    pointerof(@c)
  end

  def ins(io : Sink) : Nil
    io.put("String")
  end
end

class Class
  def ins(io : Sink) : Nil
    io.put({{ @type.name.stringify }})
  end
end

class Abcde
  def initialize
  end
end

def pp1(o, io)
  o.ins(io)
  o
end

c = Cnt.new
pp1(Abcde.new.class, c)
LibC.exit(c.n == 5 ? 3 : 1)
CR
cat >"$WORK_DIR/dot_class_p.cr" <<'CR'
class Abcde
  def initialize
  end
end

p Abcde.new.class
CR
build() {
  local name="$1"; shift
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" "$@" -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
}
build np_dot_class --no-prelude
if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/np_dot_class.run.log"; then
  echo "case np_dot_class failed:" >&2
  cat "$WORK_DIR/np_dot_class.run.log" >&2
  exit 1
fi
build dot_class_p
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/dot_class_p.run.log" ||
   ! awk '/=== STDOUT ===/{f=1;next} /=== STDERR ===/{f=0} f' "$WORK_DIR/dot_class_p.run.log" | grep -qx 'Abcde'; then
  echo "case dot_class_p failed:" >&2
  cat "$WORK_DIR/dot_class_p.run.log" >&2
  exit 1
fi
echo static_dot_class_arg_type_value_repro_ok
