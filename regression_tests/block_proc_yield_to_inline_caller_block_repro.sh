#!/usr/bin/env bash
# A yield-function containing `return` is not inlined; its block is lowered as
# a standalone block proc. When that block itself contains `yield` belonging to
# an enclosing *inlined* yield-function, the caller block only exists on the
# inline-yield stack. lower_block_to_proc used to clear that stack, so the
# nested `yield` lowered to a target-less nil and the predicate was always
# false (count_x returned 0). In stage1 this made `count_params` return 0 in
# the def prefix reselect loop, so stage2 rejected every overload.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block_proc_yield_inline.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class C
  def each_x(n : Int32, &)
    return if n == 0
    yield 1
    yield 2
    yield 3
  end

  def count_x(n : Int32, &) : Int32
    count = 0
    each_x(n) { |p| count += 1 if yield p }
    count
  end

  def run(limit : Int32) : Int32
    count_x(3) { |p| p > limit }
  end
end

c = C.new
LibC.exit(1) unless c.run(1) == 2
LibC.exit(2) unless c.run(0) == 3
LibC.exit(3) unless c.count_x(0) { |p| true } == 0
LibC.exit(0)
CR
cat >"$WORK_DIR/pl.cr" <<'CR'
class C
  private def each_x(xs : Array(Int32), &)
    return if xs.size == 0
    xs.each { |p| yield p }
  end

  @[AlwaysInline]
  private def count_x(xs : Array(Int32), &) : Int32
    count = 0
    each_x(xs) { |p| count += 1 if yield p }
    count
  end

  def run(xs : Array(Int32), limit : Int32) : Int32
    count_x(xs) { |p| p > limit }
  end
end

c = C.new
exit 1 unless c.run([1, 2, 3], 1) == 2
exit 2 unless c.run([] of Int32, 0) == 0
exit 0
CR
for name in np pl; do
  flags=()
  [[ "$name" == np ]] && flags=(--no-prelude)
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
echo block_proc_yield_to_inline_caller_block_repro_ok
