#!/usr/bin/env bash
# A raw block thunk read every capture through its global closure cell, so a
# branch proof on a capture the thunk never assigns did not survive: `if
# capture` held for one read only, and `next unless member.is_a?(DefNode)`
# never narrowed it at all. Stage 2 stopped with "no overload matches
# Adamas::HIR::AstToHir#qualify_method_annotation_in_namespace for argument
# types (Nil | String, String, Hash(String, String))" and then "no overload
# matches Adamas::HIR::AstToHir#registration_member_arena_for for argument
# types (String, DefNode | IncludeNode)". Such a capture keeps one value for
# the whole run of the thunk; it is now read once into a thunk local.
# The `next` in each block keeps it a raw thunk.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closure-cell-read-only.XXXXXX")"

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

# The stage 2 shape: a read-only capture read twice and after a call.
add_case read_only_reads_after_call 16 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? nil : Str.new(4)
    eachp(ps) do |pp|
      next if pp.n == 0
      if iname
        mark(iname, iname)
        touch
        mark(iname, iname)
      end
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

add_case read_only_ternary_call_between 16 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? nil : Str.new(4)
    if t = iname
      iname = t.prefixed if ps.a.n == 77
    end
    eachp(ps) do |pp|
      next if pp.n == 0
      r = if iname
            mark(iname, iname)
            x = pp.n > 3 ? tname(pp) : nil
            mark(iname, iname)
            1
          else
            2
          end
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

add_case read_only_nested_block_and_if 24 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? nil : Str.new(4)
    eachp(ps) do |pp|
      next if pp.n == 0
      if iname
        mark(iname, iname)
        rep(1) { |j| touch }
        if pp.n == 5
          touch
        end
        mark(iname, iname)
      end
      add(iname ? iname.v : 1000)
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

add_case read_only_and_operand 16 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? nil : Str.new(4)
    eachp(ps) do |pp|
      next if pp.n == 0
      if iname && pp.n > 0
        mark(iname, iname)
        touch
        mark(iname, iname)
      end
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'


# `is_a?` on a read-only capture, branch and guard forms, read after calls.
add_case read_only_is_a_branch 220 '
class W
  def use_p(p : P) : Int32
    p.n
  end

  def run(ps : Pair) : Int32
    eachp(ps) do |pp|
      next if pp.n == 0
      it = pp.n == 5 ? pp : Str.new(1)
      rep(2) do |q|
        next if q > 5
        if it.is_a?(P)
          touch
          add(use_p(it))
          touch
          add(use_p(it))
        else
          add(100)
        end
      end
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

add_case read_only_is_a_guard 20 '
class W
  def use_p(p : P) : Int32
    p.n
  end

  def run(ps : Pair) : Int32
    eachp(ps) do |pp|
      next if pp.n == 0
      it = pp.n == 5 ? pp : Str.new(1)
      rep(2) do |q|
        next if q > 5
        next unless it.is_a?(P)
        touch
        add(use_p(it))
        touch
        add(use_p(it))
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
  printf '%d closure-cell read-only capture case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all closure-cell read-only capture cases passed\n'
