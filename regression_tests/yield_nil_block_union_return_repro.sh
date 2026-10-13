#!/usr/bin/env bash
# `return yield` inside a method returning `Nil | T`, called with `{ nil }`.
# The block proc really returns Nil (its descriptor and the HIR yield agree),
# but lower_yield used the union recovered from users as the callback ABI:
# `call %union %block()` against a void proc read garbage, so `.nil?` was
# false. The union is only the post-call wrap target.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yield_nil_block_union.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun getpid : Int32
end

def g(x : Int32)
  h(x) { nil }
end

def h(x : Int32, &)
  return yield if x > 3
  x &+ 1
end

LibC.exit(2) unless g(LibC.getpid).nil?
LibC.exit(0)
CR
cat >"$WORK_DIR/pl.cr" <<'CR'
def f(x : Int32)
  return nil if x > 3
  x.to_i64
end

def g(x : Int32)
  h(x) { nil }
end

def h(x : Int32, &)
  return yield if x > 3
  x.to_i64
end

exit 1 unless f(ARGV.size + 5).nil?
exit 2 unless g(ARGV.size + 5).nil?
exit 3 unless g(ARGV.size) == 0_i64
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
echo yield_nil_block_union_return_repro_ok
