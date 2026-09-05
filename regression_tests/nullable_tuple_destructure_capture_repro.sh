#!/usr/bin/env bash
# Regression: destructuring a nullable Tuple in a captured block must preserve
# each element's pointer representation across the block boundary.  The direct
# helper is a same-block control; the wrapper branch is the cross-block case
# that previously spilled Node and Arena values as i32 before inttoptr.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nullable_tuple_destructure_capture.XXXXXX")"
SOURCE="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

cat >"$SOURCE" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Node
  @value : Int32 = 73

  def value : Int32
    @value
  end
end

class Arena
  def marker : Int32
    17
  end
end

class OtherArena
  def marker : Int32
    29
  end
end

def resolve(flag : Bool) : Tuple(String, Node, Arena | OtherArena)?
  flag ? {"node", Node.new, Arena.new} : nil
end

# Same-block control: the non-Nil branch narrows the Tuple before its
# destructured positions are consumed.
def direct(resolved : Tuple(String, Node, Arena | OtherArena)?) : Int32
  if resolved
    name, node, arena = resolved
    node.value
  else
    0
  end
end

LibC.exit(1) unless direct(resolve(true)) == 73
LibC.exit(2) unless direct(resolve(false)) == 0
LibC.exit(3) unless resolve(false).nil?

def wrapper(&)
  yield
end

# The captured local and the nested branch force the destructured values to
# cross a block boundary.  The nil branch and final guard keep the nullable
# carrier checks in this regression as well.
resolved = nil.as(Tuple(String, Node, Arena | OtherArena)?)
wrapper do
  if resolved = resolve(true)
    name, node, arena = resolved
    if resolve(false)
      LibC.exit(4)
    end
    LibC.exit(5) unless node.value == 73
  else
    LibC.exit(7)
  end
end
LibC.exit(8) if resolved.nil?
LibC.exit(0)
CRYSTAL

set +e
ADAMAS_DISABLE_INLINE_YIELD=1 "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 \
  "$SOURCE" --no-prelude -o "$BIN" >"$COMPILE_LOG" 2>&1
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "FAIL: nullable Tuple captured destructure did not compile (rc=$compile_status)" >&2
  tail -120 "$COMPILE_LOG" >&2
  exit 1
fi

set +e
ADAMAS_DISABLE_INLINE_YIELD=1 "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 10 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  echo "FAIL: nullable Tuple captured destructure runtime check failed (rc=$run_status)" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "nullable_tuple_destructure_capture_ok"
