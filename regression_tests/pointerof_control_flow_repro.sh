#!/usr/bin/env bash
# Address-taken values must have initialized, shared storage across CFG paths.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pointerof_control_flow.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/probe.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun memset(buffer : Void*, value : Int32, size : UInt64) : Void*
end
def branch_join(flag : Bool) : Int32
  value = 1
  if flag
    pointerof(value).value = 42
  end
  value
end
def loop_write : Int32
  value = 1
  i = 0
  while i < 3
    if i == 1
      LibC.memset(pointerof(value).as(Void*), 42, 4_u64)
    end
    i += 1
  end
  value
end
def repeat_address(flag : Bool) : Int32
  value = 1
  if flag
    pointerof(value).value = 42
  end
  pointerof(value).value
end
def parameter_write(value : Int32, flag : Bool) : Int32
  if flag
    pointerof(value).value = 42
  end
  value
end
def phi_consumer(change : Bool, choose : Bool) : Int32
  value = 1
  if change
    pointerof(value).value = 42
  end
  choose ? value : 7
end
def two_phi_values(flag : Bool) : Int32
  if flag
    a = 1
    b = 3
  else
    a = 2
    b = 4
  end
  pointerof(a).value = 42
  pointerof(b).value = 43
  a + b
end
LibC.exit(31) unless branch_join(true) == 42
LibC.exit(32) unless branch_join(false) == 1
LibC.exit(33) unless loop_write == 707406378
LibC.exit(34) unless repeat_address(true) == 42
LibC.exit(35) unless repeat_address(false) == 1
LibC.exit(36) unless parameter_write(1, true) == 42
LibC.exit(37) unless parameter_write(1, false) == 1
LibC.exit(38) unless phi_consumer(true, true) == 42
LibC.exit(39) unless phi_consumer(false, true) == 1
LibC.exit(40) unless phi_consumer(true, false) == 7
LibC.exit(41) unless two_phi_values(true) == 85
LibC.exit(42) unless two_phi_values(false) == 85
LibC.exit(0)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 \
  "$WORK_DIR/probe.cr" --no-prelude -o "$WORK_DIR/probe" \
  >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/probe" 5 512 \
  >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo pointerof_control_flow_repro_ok
