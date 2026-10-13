#!/usr/bin/env bash
# A Class#m target on a type-literal receiver (`Abcde.insp(c)`) was rebound by
# repair_receiver_bound_call_targets through the instance hierarchy, turning
# Class#insp into Base#insp (instance method, null self). A type value is an
# instance of its metaclass: Class/Module targets must be left as-is.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/type_literal_meta_method.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_meta.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun strlen(s : UInt8*) : UInt64
end

class String
  def to_unsafe : UInt8*
    pointerof(@c)
  end
end

class Cnt
  @n = 0_u64

  def put(s : String) : Nil
    @n += LibC.strlen(s.to_unsafe)
  end

  def n
    @n
  end
end

class Base
  def insp(io : Cnt) : Nil
    io.put("instance-method")
  end
end

class Class
  def insp(io : Cnt) : Nil
    tos(io)
  end

  def tos(io : Cnt) : Nil
    io.put({{ @type.name.stringify }})
  end
end

class Abcde < Base
  def initialize
  end
end

c = Cnt.new
Abcde.insp(c)
LibC.exit(c.n == 5 ? 3 : (c.n == 15 ? 4 : 1))

CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/np_meta.cr" --no-prelude -o "$WORK_DIR/np_meta" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/np_meta" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/run.log"; then
  echo "np_meta failed (want EXIT 3; 4 = instance method dispatched):" >&2
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo type_literal_meta_method_not_instance_repro_ok
