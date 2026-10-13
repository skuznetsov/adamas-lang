#!/usr/bin/env bash
# `d, a = @store[key]` inside an instance method: the `[]` target is still
# pending (queued by lower_function_if_needed) and get_function_return_type
# does not force-lower from inside a method body, so lower_index typed the call
# with the POINTER placeholder and destructuring lost the union element type.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ivar_index_destructure.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class AArena
  def initialize(@s : Int32); end
  def size; @s; end
end
class VArena
  def size; 99; end
end
class PArena
  def size; 77; end
end
alias L = AArena | VArena | PArena
class MDef
  def initialize(@n : Int32); end
  def n; @n; end
end
class Store
  def initialize(@d : MDef, @a : L); end
  def [](key)
    {@d, @a}
  end
end
class K
  def initialize(@store : Store); end
  def use : Int32
    d, a = @store[1]
    return 11 unless a.is_a?(AArena)
    return 12 unless a.size == 29
    return 13 unless d.n == 5
    0
  end
end
k = K.new(Store.new(MDef.new(5), AArena.new(29)))
LibC.exit(k.use)
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
echo ivar_index_tuple_destructure_repro_ok
