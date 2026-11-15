#!/usr/bin/env bash
# Regression: a loop variable written by an inlined yield block in one
# branch arm must merge with the other arms at the join.
#
# Inside a callee loop, a yielded block's write to a caller local is kept as
# the loop's back-edge value while the caller frame keeps its binding. That
# back-edge value was global, not path state: a write in one arm of an
# if/ternary/unless/&&/||/case leaked into the other arms and past the join,
# so the back edge and later yields read a value that does not dominate them
# (printf-style `while; if c; yield a; end; end` loops lost writes). Two
# yields in one iteration and a top-level loop are controls.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-inline_yield_loop_backedge_join.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > if_without_else.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    if n < 2
      yield n &+ 1
    end
    n &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc)
CR

cat > if_else_both_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    if n == 0
      yield 1
    else
      yield 2
    end
    n &+= 1
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > unless_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    unless n == 0
      yield 2
    end
    n &+= 1
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > and_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    n == 1 && yield(2)
    n &+= 1
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > or_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    n == 1 || yield(2)
    n &+= 1
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > case_when_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    case
    when n == 1 then yield 2
    end
    n &+= 1
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > if_elsif_else_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    if n == 0
      yield 1
    elsif n == 1
      yield 2
    else
      yield 3
    end
    n &+= 1
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > case_tuple_arg_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Tuple
  def at(index : Int32)
    {% for i in 0...T.size %}
      return self[{{i}}] if {{i}} == index
    {% end %}
    self[0]
  end
end

module M
  def self.pr(fmt : Int32, *args, &)
    i = 0
    n = 0
    while n < fmt
      case
      when n == 0 || n == 1
        arg = args.at(i)
        if arg.is_a?(Int32)
          yield arg
        else
          yield -1
        end
        i &+= 1
      end
      n &+= 1
    end
  end
end
acc = 0
M.pr(2, 1, 2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc)
CR

cat > yield_after_if_join.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    if n == 0
      yield 1
    end
    yield 2
    n &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > yield_after_loop.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    if n == 0
      yield 1
    end
    n &+= 1
  end
  yield 5
end
acc = 0
pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > two_ifs_two_locals.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    if n == 1
      yield 4
    end
    if n != 1
      yield 6
    end
    n &+= 1
  end
end
acc = 0
x = 0
pr(3) { |v| acc = acc &* 10 &+ v; x = v }
LibC.exit((acc &+ x) & 255)
CR

cat > next_after_yield_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    n &+= 1
    if n == 2
      yield 5
      next
    end
    yield n
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > top_level_loop_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
acc = 0
n = 0
while n < 2
  if n < 2
    acc = acc &* 10 &+ (n &+ 1)
  end
  n &+= 1
end
LibC.exit(acc)
CR

cat > unconditional_yield_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    yield n &+ 1
    n &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc)
CR

cat > two_yields_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    yield 1
    yield 2
    n &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > break_yield_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    if n == 1
      yield 1
      break
    end
    n &+= 1
  end
  yield 5
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

exit_code() {
  local out
  out="$("$safe" "$1" 5 256 2>&1 || true)"
  printf '%s\n' "$out" | sed -n 's/^\[EXIT: \([0-9-]*\)\].*/\1/p' | tail -1
}

fail=0
check() {
  local case_name="$1" want="$2" got_original got_candidate
  "$safe" "$original" 120 4096 build "$case_name.cr" --prelude=empty --single-module \
    --no-debug "${original_flags[@]}" -o "$case_name.original" > "$case_name.original.log" 2>&1 ||
    { cat "$case_name.original.log" >&2; echo "ORACLE_BUILD_FAIL $case_name"; fail=1; return; }
  got_original="$(exit_code "$work/$case_name.original")"
  if [[ "$got_original" != "$want" ]]; then
    echo "ORACLE_MISMATCH $case_name: original=$got_original expected=$want"; fail=1; return
  fi
  if ! "$safe" "$candidate" 120 4096 "$case_name.cr" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$case_name.candidate" > "$case_name.candidate.log" 2>&1; then
    echo "FAIL $case_name: candidate compile failed"
    grep -a -m3 -i error "$case_name.candidate.log" || true
    fail=1; return
  fi
  got_candidate="$(exit_code "$work/$case_name.candidate")"
  if [[ "$got_candidate" != "$want" ]]; then
    echo "FAIL $case_name: candidate=$got_candidate expected=$want"; fail=1; return
  fi
  echo "ok $case_name"
}

check if_without_else 12
check if_else_both_yield 122
check unless_yield 22
check and_yield 2
check or_yield 22
check case_when_yield 2
check if_elsif_else_yield 123
check case_tuple_arg_yield 12
check yield_after_if_join 122
check yield_after_loop 15
check two_ifs_two_locals 140
check next_after_yield_control 153
check top_level_loop_control 12
check unconditional_yield_control 12
check two_yields_control 188
check break_yield_control 15

[[ $fail == 0 ]] || exit 1
printf 'PASS inline_yield_loop_backedge_join\n'
