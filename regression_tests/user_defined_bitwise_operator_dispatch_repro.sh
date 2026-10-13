#!/usr/bin/env bash
# A user-defined bitwise/wrapping operator (`Set#|`, `Flags#&`, `#>>`, `#//`,
# `#&+`, ...) on a non-primitive receiver must dispatch to the method. V2's
# lower_binary only routed + - * / % and comparisons to a call; the rest fell
# into the primitive BinaryOp table and became a raw integer op over the
# receiver pointers' first words (S2 crashed on `names | bound` of two Sets).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/user_defined_bitwise_op.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

struct S
  def initialize(@v : Int32); end
  def v; @v; end
  def |(other : S) : S; S.new(@v + other.v * 10); end
  def &(other : S) : S; S.new(@v + other.v * 20); end
  def ^(other : S) : S; S.new(@v + other.v * 30); end
  def >>(other : S) : S; S.new(@v + other.v * 40); end
  def //(other : S) : S; S.new(@v + other.v * 50); end
  def &+(other : S) : S; S.new(@v + other.v * 60); end
  def &-(other : S) : S; S.new(@v + other.v * 70); end
  def &*(other : S) : S; S.new(@v + other.v * 80); end
end

class Box
  def initialize(@v : Int32); end
  def v; @v; end
  def |(other : Box) : Box; Box.new(@v + other.v * 10); end
  def &(other : Box) : Box; Box.new(@v + other.v * 20); end
end

struct G(T)
  def initialize(@v : T); end
  def v; @v; end
  def |(other : G(T)) : G(T); G(T).new(@v + other.v * 10); end
end

code = 0
code |= 1 if (S.new(1) | S.new(2)).v != 21
code |= 2 if (S.new(1) & S.new(2)).v != 41
code |= 4 if (S.new(1) ^ S.new(2)).v != 61
code |= 8 if (S.new(1) >> S.new(2)).v != 81
code |= 16 if (S.new(1) // S.new(2)).v != 101
code |= 32 if (S.new(1) &+ S.new(2)).v != 121
code |= 64 if (S.new(1) &- S.new(2)).v != 141
code |= 128 if (S.new(1) &* S.new(2)).v != 161
code |= 256 if (Box.new(1) | Box.new(2)).v != 21
code |= 512 if (Box.new(1) & Box.new(2)).v != 41
code |= 1024 if (G(Int32).new(1) | G(Int32).new(2)).v != 21
# Primitive ops must stay primitive.
x = 6
code |= 2048 if (x | 1) != 7 || (x & 3) != 2 || (x ^ 5) != 3 || (x >> 1) != 3 || (x // 4) != 1
LibC.exit(code == 0 ? 3 : (code > 200 ? 200 : code) + 10)
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
