#!/usr/bin/env bash
# A user-defined unary `-`/`~` on a struct or class (`Time::Span#-`,
# `Vector#-`) must dispatch to the method. V2's lower_unary mapped every
# `-`/`&-`/`~` to the primitive UnaryOp table, negating the receiver pointer.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/user_defined_unary_op.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

struct S
  def initialize(@v : Int32); end
  def v; @v; end
  def -; S.new(100 - @v); end
  def ~; S.new(200 - @v); end
end

class Box
  def initialize(@v : Int32); end
  def v; @v; end
  def -; Box.new(300 - @v); end
end

code = 0
code |= 1 if (-S.new(1)).v != 99
code |= 2 if (~S.new(1)).v != 199
code |= 4 if (-Box.new(1)).v != 299
# Primitive ops must stay primitive.
x = 5
code |= 8 if -x != -5 || ~x != -6
LibC.exit(code == 0 ? 3 : code + 10)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 4096 \
    "$WORK_DIR/np.cr" --no-prelude -o "$WORK_DIR/np" >"$WORK_DIR/np.build.log" 2>&1; then
  cat "$WORK_DIR/np.build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/np" 5 512 >"$WORK_DIR/np.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/np.run.log"; then
  echo "np: want EXIT 3" >&2
  cat "$WORK_DIR/np.run.log" >&2
  exit 1
fi
echo PASS
