#!/usr/bin/env bash
# A zero-argument macro invoked in a class/struct body without parentheses
# (`twopick` rather than `twopick()`) parses as a bare IdentifierNode.
# register_class_with_name_in_current_arena only expanded CallNode macro
# invocations, so under lazy HIR the defs from the expansion never reached
# @function_defs and every call to them hit the STUB (exit 134). The
# parenthesized form and macros with arguments were unaffected.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bare_zero_arg_macro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
macro twopick
  def pick(x : Int32) : Int32
    1
  end
  def pick(x : Bool) : Int32
    2
  end
end
macro scaled
  def scaled : Int32
    @n * 3
  end
end
struct SHolder
  twopick
  scaled
  def initialize(@n : Int32)
  end
end
class CHolder
  twopick
  scaled
  def initialize(@n : Int32)
  end
end
class CChild < CHolder
end
s = SHolder.new(3)
c = CHolder.new(5)
LibC.exit(1) unless s.pick(true) == 2
LibC.exit(2) unless s.pick(7) == 1
LibC.exit(3) unless s.scaled == 9
LibC.exit(4) unless c.pick(true) == 2
LibC.exit(5) unless c.pick(7) == 1
LibC.exit(6) unless c.scaled == 15
LibC.exit(7) unless CChild.new(2).scaled == 6
LibC.exit(0)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  grep -E '^\[EXIT' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo bare_zero_arg_macro_class_body_repro_ok
