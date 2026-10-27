#!/usr/bin/env bash
# A captured `String?` local read inside a raw block thunk lives in a closure
# cell. `if m` lent its truthy proof to the first read in the then-body, but a
# ternary did not lend it to its true branch, and `&&` lent it to its right
# operand only for an `m.includes?(...)` receiver. `next if m ? !s.inc?(m) : ...`
# and `m && s.inc?(m)` reloaded `m` from the cell as `Nil | Str`. Stage 2
# stopped in HIRToMIRLowering#prepare with "no overload matches
# String#includes? for argument types (Nil | String)".
# Both now lend the proof to the first direct read, receiver or argument. The
# negative cases keep the reload when a proc that assigns the capture runs
# between the test and the read, and keep `Nil` on the right of `||`.
# The `next` in each block keeps it a raw thunk.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closure-capture-condition.XXXXXX")"

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
  def initialize(@n : Int32)
  end

  def n : Int32
    @n
  end

  def inc?(o : Str) : Bool
    @n == o.n
  end

  def inc?(o : Int32) : Bool
    @n == o
  end

  def wt(o : Str) : Int32
    o.n &* 10 &+ @n
  end

  def wn(o : Str) : Int32
    o.n &* 10
  end

  def wn(o : Nil) : Int32
    100
  end
end

class L
  def gm(z : Int32) : Str?
    z == 0 ? nil : Str.new(z)
  end

  def rep(n : Int32, &)
    i = 0
    while i < n
      yield i
      i &+= 1
    end
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

add_case next_if_ternary_arg 1 '
class L
  def run(z : Int32) : Int32
    m = gm(z)
    c = 0
    rep(3) do |q|
      s = Str.new(q)
      next if m ? !s.inc?(m) : !s.inc?(1)
      c &+= 1
    end
    c
  end
end
LibC.exit(L.new.run(2))'

add_case ternary_value_arg 63 '
class L
  def run(z : Int32) : Int32
    m = gm(z)
    c = 0
    rep(3) do |q|
      next if q > 5
      s = Str.new(q)
      c = c &+ (m ? s.wt(m) : 50)
    end
    c
  end
end
LibC.exit(L.new.run(2))'

add_case and_value_arg 7 '
class L
  def run(z : Int32) : Int32
    m = gm(z)
    c = 0
    rep(3) do |q|
      next if q > 5
      s = Str.new(q)
      ok = m && s.inc?(m)
      c = c &+ (ok ? 5 : 1)
    end
    c
  end
end
LibC.exit(L.new.run(2))'

add_case and_condition_arg 1 '
class L
  def run(z : Int32) : Int32
    m = gm(z)
    c = 0
    rep(3) do |q|
      next if q > 5
      s = Str.new(q)
      c = c &+ 1 if m && s.inc?(m)
    end
    c
  end
end
LibC.exit(L.new.run(2))'

add_case ternary_call_writes_reloads 200 '
class L
  def run(z : Int32) : Int32
    m = gm(z)
    c = 0
    rep(3) do |q|
      next if q > 5
      h = -> { m = nil; 0 }
      s = Str.new(q)
      c = c &+ (m ? (h.call; s.wn(m)) : 50)
    end
    c
  end
end
LibC.exit(L.new.run(2))'

add_case and_call_writes_reloads 114 '
class L
  def run(z : Int32) : Int32
    m = gm(z)
    c = 0
    rep(3) do |q|
      next if q > 5
      h = -> { m = nil; 0 }
      s = Str.new(q)
      r = m && (h.call; s.wn(m))
      c = c &+ (r.is_a?(Int32) ? r : 7)
    end
    c
  end
end
LibC.exit(L.new.run(2))'

add_case or_rhs_keeps_nil 12 '
class L
  def run(z : Int32) : Int32
    m = gm(z)
    c = 0
    rep(3) do |q|
      next if q > 5
      s = Str.new(q)
      c = c &+ ((m || s.wn(m) == 100) ? 4 : 1)
    end
    c
  end
end
LibC.exit(L.new.run(0))'

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
      printf 'ORACLE FAIL: original %s exited %s, not %s\n' "$name" \
        "$(exit_code_of "$WORK_DIR/$name.orig.run")" "$want" >&2
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
    grep -v '^\[RUN_SAFE' "$log" | grep -m3 -i 'error\|overload' >&2 || tail -5 "$log" >&2
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
  printf '%d condition operand case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all condition operand cases passed\n'
