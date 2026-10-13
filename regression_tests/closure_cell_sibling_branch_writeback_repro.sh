#!/usr/bin/env bash
# A raw block thunk (here: a block passed to a yield method whose body uses
# `ensure`, so it is not inlined) transports written captures through global
# closure cells. The cell stayed the preferred source of truth after the
# thunk-consuming call, so reads after an if/else merge came from the cell
# even though the sibling branch (lowered before the thunk existed) wrote only
# the local. `r = 11` in the then-branch was lost and the merge returned the
# cell's stale value. In stage2 this left lower_method's `return_type` null
# (with_type_param_map uses `begin yield ensure ... end`) and every class with
# an explicit initialize crashed. Fix: copy the cell back into the enclosing
# binding right after the call and restore the previous capture state.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closure_cell_writeback.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_wb.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class M
  @m = 0
  def with_m(e : Int32, &)
    return yield if e == 0
    @m = e
    begin
      yield
    ensure
      @m = 0
    end
  end

  # Sibling branch writes the local; the other branch writes via the thunk.
  def branch(e : Int32) : Int32
    r = 0
    if e == 0
      r = 11
    else
      with_m(e) do
        r = 22
      end
    end
    r
  end

  # Plain writes after the thunk call must be visible to later reads,
  # including on a path that never ran the thunk.
  def seq(e : Int32) : Int32
    r = 1
    with_m(e) do
      r = r * 10 + 2
    end
    r = r * 10 + 3
    if e == 5
      r = r * 10 + 4
    end
    r
  end

  # Thunk nested inside a thunk: the inner write goes back to the outer cell.
  def nested(e : Int32) : Int32
    r = 1
    with_m(e) do
      with_m(e + 1) do
        r = r * 10 + 2
      end
      r = r * 10 + 3
    end
    r
  end
end
m = M.new
LibC.exit(2) unless m.branch(0) == 11
LibC.exit(3) unless m.branch(1) == 22
LibC.exit(4) unless m.seq(1) == 123
LibC.exit(5) unless m.seq(5) == 1234
LibC.exit(6) unless m.nested(1) == 123
LibC.exit(0)
CR
for name in np_wb; do
  flags=()
  [[ "$name" == np_* ]] && flags=(--no-prelude)
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
      "$WORK_DIR/$name.cr" ${flags[@]+"${flags[@]}"} -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1; then
    echo "case $name failed:" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo closure_cell_sibling_branch_writeback_repro_ok
