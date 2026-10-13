#!/usr/bin/env bash
# A bare receiverless zero-arg self call (`out`) inside an inherited base-class
# method was lowered as a static call to the base body, while `out()` and
# `self.out` dispatched virtually. Inherited bodies are lowered once with the
# base self type, so a subclass override was unreachable: abstract targets hit
# the STUB, concrete ones silently returned the base result. In the bootstrap
# this made `MacroValue#call_method`'s bare `to_id` ignore
# MacroStringValue#to_id, so `{{ "x".id }}` kept its quotes in stage2.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bare_self_call_virtual.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
abstract class AV
  abstract def out : Int32
  def tid : Int32
    out
  end
end
class AS < AV
  def out : Int32
    99
  end
  def tid : Int32
    7
  end
end
class AN < AV
  def out : Int32
    11
  end
end
class CV
  def out : Int32
    1
  end
  def tid : Int32
    out
  end
end
class CN < CV
  def out : Int32
    22
  end
end
module MOut
  def out : Int32
    33
  end
end
class CM < CV
  include MOut
end
class CP < CV
end
class CG < CP
  def out : Int32
    44
  end
end
# Empty-body concrete base (not abstract): only the override makes it virtual.
class EB
  @v = 0
  def hook : Nil
  end
  def run : Int32
    hook
    @v
  end
end
class EO < EB
  def hook : Nil
    @v = 55
  end
end
def pick(i : Int32) : AV
  i == 0 ? AS.new : AN.new
end
LibC.exit(1) unless AN.new.tid == 11
LibC.exit(2) unless CN.new.tid == 22
LibC.exit(3) unless CV.new.tid == 1
LibC.exit(4) unless pick(0).tid == 7
LibC.exit(5) unless pick(1).tid == 11
LibC.exit(6) unless CM.new.tid == 33
LibC.exit(7) unless CG.new.tid == 44
LibC.exit(8) unless CP.new.tid == 1
LibC.exit(9) unless EO.new.run == 55
LibC.exit(10) unless EB.new.run == 0
LibC.exit(0)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo bare_self_call_virtual_dispatch_repro_ok
