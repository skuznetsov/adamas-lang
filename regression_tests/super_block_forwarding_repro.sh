#!/usr/bin/env bash
# `super { ... }` / `super(args) do ... end` must bind the block to the super
# target (like `Slice#fill(*, offset, &) = super { |i| yield i }`). V2 parsed
# the brace block as an argument, lowered the block as `.call` on the super
# result, forwarded the host's params instead of the inlined def's, dropped
# named super-arg names, and matched the target overload by arity only.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/super_block_forwarding.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/mod.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

module M
  def fill(value : Int32) : self
    @sum = @sum + value * 1000
    self
  end

  def fill(*, offset : Int32 = 0, & : Int32 -> Int32) : self
    i = 0
    while i < 3
      @sum = @sum + (yield i + offset)
      i += 1
    end
    self
  end
end

class C
  include M
  def initialize; @sum = 0; end
  def sum; @sum; end

  def fill(value : Int32) : self
    fill { value }
  end

  def fill(*, offset : Int32 = 0, & : Int32 -> Int32) : self
    super { |i| yield i }
  end
end

c = C.new
r = c.fill(5)
code = 0
code |= 2 if r.sum != 15
code |= 1 if c.sum != 15
LibC.exit(code == 0 ? 3 : code + 10)
CR
cat >"$WORK_DIR/cls.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class P
  def initialize; @sum = 0; end
  def sum; @sum; end

  def run(a : Int32, b : Int32 = 7, &)
    @sum = @sum + (yield a) + b
    self
  end

  def named(x : Int32, *, scale : Int32 = 1) : Int32
    x * scale
  end
end

class Q < P
  def run(a : Int32, b : Int32 = 7, &)
    super(a, b: 100) { |v| yield v * 2 }
  end

  def named(x : Int32, *, scale : Int32 = 1) : Int32
    super(x, scale: scale + 1)
  end
end

q = Q.new
q.run(5) { |v| v + 1 }
n = q.named(3, scale: 4)
code = 0
code |= 1 if q.sum != 111
code |= 2 if n != 15
LibC.exit(code == 0 ? 3 : code + 10)
CR
for name in mod cls; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 4096 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/$name.run.log"; then
    echo "$name: want EXIT 3" >&2
    cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo PASS
