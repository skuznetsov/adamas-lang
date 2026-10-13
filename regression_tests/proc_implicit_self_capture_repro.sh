#!/usr/bin/env bash
# A proc literal inside an instance method must capture self when its body
# makes an implicit-receiver call hidden under a node kind the capture
# walkers did not whitelist (as/is_a?/nested proc/ternary+raise) or uses a
# bare zero-arg method identifier (`v0`). V2 emitted a non-closure proc and
# the body called the method with a null self (SIGSEGV).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proc_implicit_self_capture.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/pc.cr" <<'CR'
class Foo
  def initialize(@v : Int32)
  end

  def get(n : Int32) : Int32?
    @v + n
  end

  def v0 : Int32
    @v
  end

  def sum(*xs : Int32) : Int32
    s = @v
    xs.each { |x| s += x }
    s
  end

  def mk_as : Proc(Int32, Int32?)
    ->(n : Int32) { get(n).as(Int32?) }
  end

  def mk_isa : Proc(Int32, Bool)
    ->(n : Int32) { get(n).is_a?(Int32) }
  end

  def mk_bare : Proc(Int32, Int32)
    ->(n : Int32) { v0 + n }
  end

  def mk_nested : Proc(Int32, Int32)
    ->(n : Int32) { ->(m : Int32) { v0 + m }.call(n) }
  end


  def mk_local_as(k : Int32?) : Proc(Int32, Int32)
    ->(n : Int32) { k.as(Int32) + n }
  end

  def mk_raise : Proc(Int32, Int32)
    ->(n : Int32) { n > 100 ? raise(msg(n)) : n + @v }
  end

  def msg(n : Int32) : String
    "big #{n}"
  end
end

f = Foo.new(40)
r = 0
r |= 1 unless f.mk_as.call(2) == 42
r |= 4 unless f.mk_isa.call(2) == true
r |= 8 unless f.mk_bare.call(2) == 42
r |= 16 unless f.mk_nested.call(2) == 42
r |= 64 unless f.mk_local_as(40).call(2) == 42
r |= 128 unless f.mk_raise.call(2) == 42
STDERR.puts "r=#{r}"
exit(r == 0 ? 3 : 1)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/pc.cr" -o "$WORK_DIR/pc" >"$WORK_DIR/pc.build.log" 2>&1; then
  cat "$WORK_DIR/pc.build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/pc" 5 512 >"$WORK_DIR/pc.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/pc.run.log"; then
  echo "pc: want EXIT 3" >&2
  cat "$WORK_DIR/pc.run.log" >&2
  exit 1
fi
echo proc_implicit_self_capture_repro_ok
