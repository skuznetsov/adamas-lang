#!/usr/bin/env bash
# A bare zero-arg call on a subclass (`Leaf.new.tag`) must bind the inherited
# nilary `Base#tag` even when a nearer ancestor (class body or included
# module) defines a same-named `tag(flag)`. V2 resolved the return type and
# the body through arity-less lookups (typing the call as the arity-1
# overload's Bool, or finding no body at all and emitting a stub), lost the
# module def's arena, and let the zero-arg callsite record veto the inherited
# nilary target.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inherited_zero_arg_overload.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/cls.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class Base
  def tag
    40 + 2
  end
end

class Mid < Base
  def tag(flag)
    flag == 1
  end
end

class Leaf < Mid
end

x = Leaf.new.tag
y = x + 1
LibC.exit(y == 43 ? 3 : 10)
CR
cat >"$WORK_DIR/mod.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

module Flagged
  def tag(flag)
    flag == 1
  end
end

class Base
  def tag
    40 + 2
  end
end

class Mid < Base
  include Flagged
end

class Leaf < Mid
end

class Other < Base
  def tag(flag)
    flag == 2
  end
end

def via_def
  Leaf.new.tag + 0
end

code = 0
code |= 1 if Leaf.new.tag() + 1 != 43
code |= 2 if via_def != 42
o = Other.new
code |= 4 if o.tag + 2 != 44
code |= 8 unless o.tag(2)
LibC.exit(code == 0 ? 3 : code + 10)
CR
cat >"$WORK_DIR/moddef.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

module Flagged
  def tag(flag)
    flag == 1
  end
end

class Base
  def tag
    40 + 2
  end
end

class Mid < Base
  include Flagged
end

class Leaf < Mid
end
def via_def
  Leaf.new.tag + 0
end
LibC.exit(via_def == 42 ? 3 : 10)
CR
for name in cls mod moddef; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 4096 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/$name.run.log"; then
    echo "$name: want EXIT 3" >&2
    cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo PASS
