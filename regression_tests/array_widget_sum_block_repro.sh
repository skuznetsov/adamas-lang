#!/usr/bin/env bash
# Regression guard for Array#sum { } over abstract/base-class elements.
#
# V2 used to lower the stdlib Enumerable#sum/Reduce path with Pointer-typed
# elements for Array(Widget), then emit Pointer#width instead of virtual
# Widget#width. The reduced shape below must keep the block parameter typed as
# Widget and dispatch width virtually.
#
# Exit contract:
#   0 — fixed: Array#sum block dispatches through Widget#width.
#   1 — reproduced: binary ran but did not print the fixed marker.
#   2 — invalid invocation (missing compiler arg).
#   >2 — unexpected compile/runtime failure.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array_widget_sum_block.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
abstract class Widget
  abstract def width : Int32
end

class Label < Widget
  def initialize(@text : String)
  end

  def width : Int32
    @text.size
  end
end

class Button < Widget
  def initialize(@label : String)
  end

  def width : Int32
    @label.size + 4
  end
end

items = [] of Widget
items << Label.new("Hello")
items << Button.new("OK")
items << Button.new("Cancel")

if items.sum { |item| item.width } == 21
  puts "array_widget_sum_block_ok"
else
  puts "array_widget_sum_block_FAIL"
end
CR

compile_cmd=()
if [[ "$(basename "$COMPILER")" == "crystal" ]]; then
  compile_cmd=("$COMPILER" build "$SRC" -o "$BIN")
else
  compile_cmd=("$COMPILER" "$SRC" -o "$BIN")
fi

set +e
"${compile_cmd[@]}" >"$TMP_DIR/compile.out" 2>&1
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "unexpected: compile failed with status=$compile_status" >&2
  tail -20 "$TMP_DIR/compile.out" >&2
  exit 3
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

if grep -qF "array_widget_sum_block_ok" "$RUN_LOG"; then
  echo "fixed: Array#sum block keeps abstract element receiver type"
  cat "$RUN_LOG"
  exit 0
fi

if [[ $run_status -eq 0 ]]; then
  echo "reproduced: fixed marker missing despite exit 0" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "unexpected: abnormal exit ($run_status)" >&2
echo "--- run log tail ---" >&2
tail -20 "$RUN_LOG" >&2
exit 4
