#!/usr/bin/env bash
# The Array#count and Array#reduce HIR intrinsics hand-build their loop phis.
# They used body_block as the phi predecessor for the edge leaving the block
# body, but a body containing `&&`/`if` ends in a different block. The phi
# then took the value from a non-predecessor and the count/accumulator was
# wrong (count gave 1 instead of 2). In stage1 this miscounted required
# parameters in the def prefix scan, so stage2 left K#initialize bodyless.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array_count_split_pred.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
class Prm
  getter is_splat : Bool
  getter is_block : Bool

  def initialize(@is_splat : Bool = false, @is_block : Bool = false)
  end
end

class H
  def nos?(param : Prm) : Bool
    param.is_splat
  end

  def count_plain(params : Array(Prm)) : Int32
    params.count { |p| !p.is_block && !nos?(p) }
  end

  def count_if(params : Array(Prm)) : Int32
    params.count { |p| if p.is_block
      false
    else
      !nos?(p)
    end }
  end

  def reduce_split(xs : Array(Int32)) : Int32
    xs.reduce { |acc, x| (x > 1 && x < 4) ? acc + x : acc }
  end
end

ps = [Prm.new, Prm.new(is_splat: true), Prm.new, Prm.new(is_block: true)]
h = H.new
exit 1 unless h.count_plain(ps) == 2
exit 2 unless h.count_if(ps) == 2
exit 3 unless h.reduce_split([1, 2, 3, 4]) == 6
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
echo array_count_split_predicate_phi_repro_ok
