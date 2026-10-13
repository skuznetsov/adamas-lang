#!/usr/bin/env bash
# A block containing `next` was routed to proc materialization
# (inline_yield_fallback_call) instead of inline yield. `break` inside a
# proc-materialized block has no loop exit to jump to and lowered to
# `unreachable`, so `next if ...; break if ...` blocks trapped at runtime.
# In the bootstrap this killed stage2 on every prelude program at
# `compatible = false; break` in find_module_class_def's each_param block.
# Second route: a callee with an early `return` before its first yield plus a
# block assigning caller locals took the closure fallback
# (yield_return_requires_block_fallback?) even when the block had a `break`.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block_next_break.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def each_val(&)
  yield 0
  yield 1
  yield 2
  yield 3
end
def find(limit : Int32) : Int32
  score = 0
  each_val do |v|
    next if v == 0
    break if v >= limit
    score += 10
  end
  score
end
def find_value(limit : Int32) : Int32
  r = each_val do |v|
    next if v == 0
    break v * 100 if v >= limit
  end
  r ? r : -1
end
def nested_loop_break(limit : Int32) : Int32
  score = 0
  each_val do |v|
    next if v == 1
    i = 0
    while true
      break if i >= v
      i += 1
    end
    score += i
  end
  score
end
def each_early(flag : Int32, &)
  return if flag == 0
  i = 0
  while i < 3
    yield i
    i += 1
  end
end
def find_early(flag : Int32, limit : Int32) : Int32
  score = 1
  compatible = true
  each_early(flag) do |v|
    if v >= limit
      compatible = false
      break
    end
    score += 10
  end
  compatible ? score : score + 100
end
LibC.exit(5) unless find_early(0, 2) == 1
LibC.exit(6) unless find_early(1, 2) == 121
LibC.exit(7) unless find_early(1, 9) == 31
LibC.exit(1) unless find(2) == 10
LibC.exit(2) unless find(9) == 30
LibC.exit(3) unless find_value(2) == 200
LibC.exit(4) unless nested_loop_break(0) == 5
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
echo block_next_break_closure_repro_ok
