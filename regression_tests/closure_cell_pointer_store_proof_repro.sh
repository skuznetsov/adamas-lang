#!/usr/bin/env bash
# A store through a pointer (`buf.value = off`, or Array#<< once inlined)
# dropped every closure-cell write proof, even one that survives calls in the
# raw block thunk owning the cell. `t = conv(q); buf.value = off; ta(t, c)`
# then reloaded `t` from the cell as `Nil | TR`. A pointer can only reach the
# cell if the code sharing it takes the capture's address, so a call-stable
# proof now survives pointer stores unless a `pointerof` of the capture appears
# in that code. The `next` in each block keeps it a raw thunk.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closure-cell-pointer-store.XXXXXX")"

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

struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end

  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end

  @[Primitive(:pointer_get)]
  def value : T
  end
end

struct TR
  def initialize(@id : Int32)
  end

  def id : Int32
    @id
  end

  def !=(other : TR) : Bool
    @id != other.id
  end

  VOID = TR.new(0)
end

class L
  def conv(n : Int32) : TR
    TR.new(n)
  end

  def al(o : Int32, a : Int32) : Int32
    o &+ a
  end

  def ta(t : TR, c : Bool) : Int32
    t.id &+ 4
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

# Write, pointer store, read, all in the thunk owning the cell.
add_case store_in_owner 13 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    buf = Pointer(Int32).malloc(1_u64)
    t = z == 99 ? conv(1) : nil
    rep(3) do |q|
      next if q > 5
      t = conv(q)
      if t != TR::VOID
        off = al(off, 1)
        buf.value = off
        off = off &+ ta(t, c)
      end
    end
    off &+ (t ? 0 : 1000)
  end
end
LibC.exit(L.new.run(0, false))'

# The same inside the capture's sole nested writer block.
add_case store_in_nested_writer 26 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    buf = Pointer(Int32).malloc(1_u64)
    t = z == 99 ? conv(1) : nil
    rep(2) do |k|
      rep(3) do |q|
        next if q > 5
        t = conv(q)
        if t != TR::VOID
          off = al(off, 1)
          buf.value = off
          off = off &+ ta(t, c)
        end
      end
    end
    off &+ (t ? 0 : 1000)
  end
end
LibC.exit(L.new.run(0, false))'

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
  printf '%d pointer store case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all pointer store cases passed\n'
