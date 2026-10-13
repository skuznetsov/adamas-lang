#!/usr/bin/env bash
# The Array#reduce HIR intrinsic seeds the accumulator with element 0 and
# ignored call arguments, so `reduce(memo)` dropped the memo and typed the
# accumulator as the element type (Prm + Int32 -> STUB, exit 134).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array_reduce_memo.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
class Prm
  getter is_block : Bool

  def initialize(@is_block : Bool = false)
  end
end

ps = [Prm.new, Prm.new(true), Prm.new]
exit 1 unless ps.reduce(0) { |acc, p| p.is_block ? acc : acc + 1 } == 2
exit 2 unless [1, 2, 3].reduce(10) { |acc, x| acc + x } == 16
exit 3 unless [1, 2, 3].reduce { |acc, x| acc + x } == 6
exit 0
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
    "$WORK_DIR/repro.cr" -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  grep -E '^\[EXIT' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo array_reduce_memo_intrinsic_repro_ok
