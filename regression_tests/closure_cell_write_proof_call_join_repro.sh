#!/usr/bin/env bash
# A capture written inside a raw block thunk lives in a global closure cell
# typed with the capture's declared union (`Str | Nil`). The written value
# proved the narrower type only until the next call or the next block, so
# `iname = pname.at? ? pname : pname.prefixed` followed by
# `t = (e ? e[1] : nil) || tname(pp)` and `mark(owner, iname, t) if t`
# reloaded `iname` as `Nil | Str`. Stage 2 stopped with "no overload matches
# Adamas::HIR::AstToHir#mark_declared_ivar_type for argument types
# (String, Nil | String, String)".
# The proof now survives calls when no closure nested in the thunk assigns the
# capture, and it crosses if/unless/ternary/`||` joins when every reaching arm
# keeps it. The negative cases pin the reloads: a nil-writing arm, a nested
# proc or block that writes the capture during a later call, and a loop whose
# back edge carries a later write.
# The `next` in each block keeps it a raw thunk: without it the block is
# inlined into the forwarding block's thunk and the capture is a plain local.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closure-cell-proof.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  {
    cat <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Str
  def initialize(@v : Int32)
  end

  def v : Int32
    @v
  end

  def at? : Bool
    @v > 100
  end

  def prefixed : Str
    Str.new(@v &+ 1)
  end
end

class P
  def initialize(@n : Int32)
  end

  def n : Int32
    @n
  end
end

class Pair
  def initialize(@a : P, @b : P)
  end

  def a : P
    @a
  end

  def b : P
    @b
  end
end

class W
  @sum = 0
  @calls = 0

  def sum : Int32
    @sum
  end

  def add(x : Int32) : Nil
    @sum = @sum &+ x
  end

  def touch : Nil
    @calls = @calls &+ 1
  end

  def rep(n : Int32, &)
    i = 0
    while i < n
      yield i
      i &+= 1
    end
  end

  # The `next` inside the forwarding block keeps the caller's block a raw
  # thunk instead of an inlined yield.
  def eachp(ps : Pair, &)
    if ps.a.n > 0
      rep(2) do |i|
        next if i > 5
        yield(i == 0 ? ps.a : ps.b)
      end
    else
      yield ps.b
    end
  end

  def name_of(p : P) : Str?
    p.n > 0 ? Str.new(p.n) : nil
  end

  def entry(i : Int32) : Tuple(Str, Str?)?
    i == 7 ? {Str.new(30), nil} : nil
  end

  def tname(p : P) : Str?
    p.n > 3 ? Str.new(1) : nil
  end

  def mark(name : Str, t : Str) : Nil
    @sum = @sum &+ name.v
  end

  def anyv(ps : Pair, &) : Bool
    yield ps.a
  end
end
HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

# name:expected-exit
CASES=()

add_case() {
  CASES+=("$1:$2")
  write_case "$1" "$3"
}

# The stage 2 shape: ternary and `||` joins plus calls between write and read.
add_case write_then_join_and_call 212 '
class W
  def run(ps : Pair) : Int32
    idx = 0
    iname = idx == 99 ? Str.new(1) : nil
    eachp(ps) do |pp|
      e = entry(idx)
      idx &+= 1
      pname = e ? e[0] : name_of(pp)
      next unless pname
      iname = pname.at? ? pname : pname.prefixed
      t = (e ? e[1] : nil) || tname(pp)
      mark(iname, t) if t
      next if anyv(ps) { |q| q.n == iname.v }
      add(100)
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(5))))'

add_case write_then_call 11 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? Str.new(1) : nil
    eachp(ps) do |pp|
      next if pp.n == 0
      iname = Str.new(pp.n)
      touch
      mark(iname, iname)
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

add_case write_then_if_join 21 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? Str.new(1) : nil
    eachp(ps) do |pp|
      next if pp.n == 0
      iname = Str.new(pp.n)
      if pp.n == 5
        touch
      elsif pp.n == 6
        add(10)
      else
        add(1000)
      end
      unless pp.n == 0
        touch
      end
      mark(iname, iname)
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

# One arm writes nil: the join keeps no proof and the read reloads the cell.
add_case nil_arm_reloads 56 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? Str.new(1) : nil
    eachp(ps) do |pp|
      next if pp.n == 0
      iname = Str.new(pp.n)
      if pp.n == 5
        iname = nil
      end
      touch
      add((x = iname) ? x.v : 50)
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

# A proc literal in the thunk writes the capture when a later call runs it.
add_case proc_literal_write_reloads 80 '
class W
  def callp(f : Proc(Int32)) : Int32
    f.call
  end

  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? Str.new(1) : nil
    eachp(ps) do |pp|
      next if pp.n == 0
      f = -> { iname = Str.new(40); 0 }
      iname = Str.new(1)
      callp(f)
      add((x = iname) ? x.v : 7)
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

# A nested raw block writes the capture.
add_case nested_block_write_reloads 60 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? Str.new(1) : nil
    eachp(ps) do |pp|
      next if pp.n == 0
      iname = Str.new(1)
      rep(1) do |i|
        next if i > 5
        iname = Str.new(30)
      end
      touch
      add((x = iname) ? x.v : 7)
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

# The loop back edge carries the later write into the next read.
add_case loop_back_edge_reloads 24 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? Str.new(1) : nil
    eachp(ps) do |pp|
      next if pp.n == 0
      j = 0
      iname = Str.new(3)
      while j < 2
        touch
        add((x = iname) ? x.v : 7)
        iname = Str.new(9)
        j &+= 1
      end
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}" want="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$want" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$want" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}" want="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s: compile failed\n' "$name" >&2
    tail -5 "$log" >&2
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  got="$(exit_code_of "$run_log")"
  if [[ "$got" == "$want" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: exit %s, expected %s\n' "$name" "$got" "$want" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d closure-cell write proof case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all closure-cell write proof cases passed\n'
