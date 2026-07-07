#!/usr/bin/env bash
# Known-red reducer for: phantom generic type synthesized from a constructor
# call inside a proc-materialized (inline-fallback) block.
# Documented in ../KNOWN_BUGS.md.
#
# `Box` is NOT generic, but lowering `Box.new(6)` as the tail of a block that
# reaches the inline-yield fallback path creates a phantom type "Box(Int32)"
# with no ivar metadata: its getter lowers `@v` as a pointer field at offset 0
# (`load ptr [self+0]; load i32 [that]`) while `initialize` stores the i32 at
# its real offset. The getter then dereferences the object's leading bytes
# ({type_id, v} = 0x{v}0000{tid}) as a pointer -> segfault/bus error.
# Found 2026-07-07 while closing L11 (session-13); crashes on pre-L11-fix
# compilers too (independent of block-shape return contracts).
#
# Exit contract:
#   0 — reproduced: binary crashed (segfault/bus error).
#   1 — not reproduced: ran cleanly and printed the expected line (bug fixed).
#   2 — invalid invocation (missing compiler arg).
#   >2 — unexpected failure (compile error, wrong output, timeout, ...).
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phantom_generic_ctor.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
class Box
  def initialize(@v : Int32)
  end

  def v : Int32
    @v
  end
end

class Ctx
  @depth = 0

  def with_map(m : Int32, &)
    old = @depth
    @depth = m
    begin
      yield
    ensure
      @depth = old
    end
  end
end

ctx = Ctx.new

# Triple nesting exceeds INLINE_YIELD_MAX_REPEAT=2 so the innermost callsite
# takes the inline-yield fallback (proc-materialized) path. Two callsites of
# the same block return shape; blocks tail-call a constructor with args.
r2 = ctx.with_map(4) do
  ctx.with_map(5) do
    ctx.with_map(6) do
      Box.new(5)
    end
  end
end

r5 = ctx.with_map(13) do
  ctx.with_map(14) do
    ctx.with_map(15) do
      Box.new(6)
    end
  end
end

puts "phantom_generic_ok r2=#{r2.v} r5=#{r5.v}"
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
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 256 >"$RUN_LOG" 2>&1
run_status=$?
set -e

if grep -q "phantom_generic_ok r2=5 r5=6" "$RUN_LOG"; then
  echo "not reproduced: correct output (bug likely fixed)"
  exit 1
fi

if [[ $run_status -ne 0 ]] || grep -qE 'Segfault|Bus error|CRASH' "$RUN_LOG"; then
  echo "reproduced: crash (exit $run_status)"
  exit 0
fi

echo "unexpected: clean exit but wrong output" >&2
tail -10 "$RUN_LOG" >&2
exit 4
