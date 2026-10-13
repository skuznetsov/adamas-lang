#!/usr/bin/env bash
# `break` inside a block that is inline-yielded from an intrinsic loop must
# publish the values assigned before it to the caller's locals.
#
# Two roots, both needed for `ok = false; break` to survive:
# 1. lower_break took the loop exit block from @loop_exit_stack but the phi
#    map from @loop_phi_stack.last, which is the (exit-less) yield
#    continuation frame pushed for `next`; break_info then carried an empty
#    locals map and the exit phi fell back to the header phi.
# 2. Intrinsic loops (times/each/...) and while/loop/until registered the
#    exit phi as a function local but left the inline caller local pointing
#    at the header phi, so code after the loop read the pre-break value.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inline-yield-break.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

HEADER='lib LibC
  fun exit(code : Int32) : NoReturn
end

struct Int32
  def times(&block : self ->) : Nil
    i = self ^ self
    while i < self
      yield i
      i &+= 1
    end
  end

  def upto(to : Int32, &block : self ->) : Nil
    x = self
    while x <= to
      yield x
      x &+= 1
    end
  end
end
'

# name|expected exit code|body
cases=(
"times_forwarded|1|
class Foo
  def each_x(n : Int32, &)
    n.times { |i| yield i }
  end

  def f(n : Int32) : Bool
    ok = true
    each_x(n) do |x|
      if x == 2
        ok = false
        break
      end
    end
    ok
  end
end

a = Foo.new.f(3) ? 10 : 0
b = Foo.new.f(2) ? 1 : 0
LibC.exit(a + b)"
"upto_forwarded|5|
class Foo
  def each_x(a : Int32, b : Int32, &)
    a.upto(b) { |v| yield v }
  end

  def f : Int32
    last = 0
    each_x(3, 9) do |v|
      last = v
      break if v == 5
    end
    last
  end
end

LibC.exit(Foo.new.f)"
"while_in_times_block|36|
class Foo
  def f(n : Int32) : Int32
    acc = 0
    n.times do |i|
      j = 0
      while j < 10
        break if j == 2
        acc &+= 1
        j &+= 1
      end
      acc &+= 10
    end
    acc
  end
end

LibC.exit(Foo.new.f(3))"
)

failed=0
echo "compiler: $COMPILER"
for entry in "${cases[@]}"; do
  name="${entry%%|*}"
  rest="${entry#*|}"
  expected="${rest%%|*}"
  body="${rest#*|}"
  src="$TMP_DIR/$name.cr"
  out="$TMP_DIR/$name"
  printf '%s\n%s\n' "$HEADER" "$body" >"$src"

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 --no-prelude "$src" -o "$out" \
    >"$TMP_DIR/$name.compile.log" 2>&1
  compile_rc=$?
  set -e
  if [[ $compile_rc -ne 0 || ! -x "$out" ]]; then
    tail -40 "$TMP_DIR/$name.compile.log" >&2 || true
    echo "FAIL[$name]: compile rc=$compile_rc" >&2
    failed=1
    continue
  fi

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$out" 5 512 >"$TMP_DIR/$name.run.log" 2>&1
  set -e
  actual="$(grep -o 'EXIT: [0-9]*' "$TMP_DIR/$name.run.log" | head -1 | awk '{print $2}')"
  if [[ "$actual" != "$expected" ]]; then
    cat "$TMP_DIR/$name.run.log" >&2
    echo "FAIL[$name]: exit ${actual:-?}, expected $expected" >&2
    failed=1
  else
    echo "ok[$name]: exit $actual"
  fi
done

if [[ $failed -ne 0 ]]; then
  exit 1
fi
echo "PASS: break inside inline-yielded blocks keeps caller-local writes"
