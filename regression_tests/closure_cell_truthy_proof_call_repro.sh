#!/usr/bin/env bash
# `if capture` inside a raw block thunk proved a closure cell the thunk itself
# assigns non-nil for one read only, so `mark(iname, iname)` (or a read after
# a call) reloaded the cell as `Nil | Str`, and `if capture = expr` proved
# nothing. No closure nested in the thunk writes such a cell, so the proof
# now holds like a write proof: on its straight-line block until the next
# store or merge. The negative cases pin the reloads after a nil write.
# The `next` in each block keeps it a raw thunk.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closure-cell-truthy.XXXXXX")"

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

# `if capture = expr` proves the value just stored (register_module_instance_methods_for).
add_case assign_condition_capture 16 '
class W
  def run(ps : Pair) : Int32
    e = name_of(ps.a)
    if e2 = e
      add(1)
    end
    eachp(ps) do |pp|
      next if pp.n == 0
      rn = Str.new(3)
      if e2 = name_of(pp)
        rn = e2
      end
      mark(rn, rn)
      if e2 = tname(pp)
        mark(e2, e2)
        touch
        mark(e2, e2)
      end
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

# The thunk writes the capture: the proof lasts until the store.
add_case thunk_written_two_reads 6 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? nil : Str.new(4)
    eachp(ps) do |pp|
      next if pp.n == 0
      if iname
        mark(iname, iname)
        iname = nil if pp.n == 5
      end
      add(iname ? 100 : 1)
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

add_case thunk_written_conditional_nil_reloads 15 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? nil : Str.new(4)
    eachp(ps) do |pp|
      next if pp.n == 0
      if iname
        mark(iname, iname)
        touch
        mark(iname, iname)
        iname = nil if pp.n == 5
        add(iname ? 100 : 1)
      end
      add(iname ? 1000 : 3)
    end
    sum
  end
end
LibC.exit(W.new.run(Pair.new(P.new(5), P.new(6))))'

add_case thunk_written_nil_drops_proof 31 '
class W
  def run(ps : Pair) : Int32
    iname = ps.a.n == 99 ? nil : Str.new(4)
    eachp(ps) do |pp|
      next if pp.n == 0
      if iname
        mark(iname, iname)
        iname = nil
        add(iname ? 100 : 7)
      else
        add(20)
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
  printf '%d closure-cell truthy proof case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all closure-cell truthy proof cases passed\n'
