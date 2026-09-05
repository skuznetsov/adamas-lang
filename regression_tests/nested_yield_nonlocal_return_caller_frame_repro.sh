#!/usr/bin/env bash
set -euo pipefail

# Regression for inline_block_body losing a live caller frame through the
# nullable generic Array#[]? path. The no-context fallback then lowers the
# same nested yield body again and the stage-2 compiler exhausts its stack.
#
# Usage:
#   regression_tests/nested_yield_nonlocal_return_caller_frame_repro.sh <compiler>
#   CHECK_INDEX_CAPTURE=1 ...  # optional outer-index capture guard

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:?usage: $0 <compiler>}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_nested_yield_frame.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

# Returning the yielded value keeps the primary guard independent of the
# separate outer-index capture defect.
return_expr=value
if [[ "${CHECK_INDEX_CAPTURE:-0}" == "1" ]]; then
  # The stage-1 compilers currently lose this outer loop index (0 instead of
  # 2). Keep that independent semantic defect observable without making it
  # part of the primary nested-yield/non-local-return stack guard.
  return_expr=index
fi

cat >"$SRC" <<CR
lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

struct Walker
  @limit : Int32

  def initialize(@limit : Int32)
  end

  def each(&) : Nil
    i = 0
    while i < @limit
      yield i
      i += 1
    end
  end
end

def each_with_index(walker : Walker, &)
  i = 0
  walker.each do |value|
    yield value, i
    i += 1
  end
end

def first_match(walker : Walker) : Int32
  each_with_index(walker) do |value, index|
    if value == 2
      return ${return_expr}
    end
  end
  -1
end

matched = first_match(Walker.new(5))
missed = first_match(Walker.new(2))
LibC.printf("results=%d,%d\n", matched, missed)
CR

set +e
compiler_subcommand=()
compiler_flags=(--no-prelude)
if [[ "$(basename "$COMPILER")" == "crystal" ]]; then
  # `crystal <file>` runs the program and does not materialize -o. Build the
  # oracle through the same bounded runner used for the stage-2 compiler.
  compiler_subcommand=(build)
  compiler_flags=()
fi
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
  "${compiler_subcommand[@]}" "$SRC" "${compiler_flags[@]}" -o "$BIN" >"$COMPILE_LOG" 2>&1
compile_status=$?
set -e
if [[ "$compile_status" -ne 0 ]]; then
  echo "FAIL: nested yield/non-local return compile rc=$compile_status"
  tail -20 "$COMPILE_LOG" || true
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e
if [[ "$run_status" -ne 0 ]]; then
  echo "FAIL: nested yield/non-local return runtime rc=$run_status"
  cat "$RUN_LOG"
  exit 1
fi
stdout_text="$(awk '/^=== STDOUT ===$/{inside=1; next} /^=== STDERR ===$/{inside=0} inside' "$RUN_LOG" | tr -d '\r')"
if [[ "$stdout_text" != "results=2,-1" ]]; then
  echo "FAIL: expected stdout results=2,-1"
  cat "$RUN_LOG"
  exit 1
fi

echo "OK: nested yield/non-local return preserved caller frame"
