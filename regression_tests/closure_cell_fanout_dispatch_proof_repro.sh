#!/usr/bin/env bash
# A call whose union or parent-class argument fans out over several overloads
# (`IVarInfo.new(ivar_name, ...)` with `ivar_name : String?`, or `kd(pick(q))`
# with `kd(Ba)`/`kd(Su)`) is lowered as compiler-generated branches that rejoin
# in a fresh block. A closure-cell write proof is bound to the block where it
# was taken, so the read after the fanout, `ta(t, c)`, reloaded `t` from the
# cell as `Nil | TR`. Stage 2 stopped with "no overload matches
# Adamas::HIR::AstToHir#field_storage_size for argument types
# (Nil | Adamas::HIR::TypeRef, Bool)".
# The fanout arms run only the dispatched calls over already-lowered values, so
# a proof still registered unchanged after them held on every arm; it is now
# carried into the join block. The two negative cases keep the reload when the
# dispatched call runs a proc that assigns the capture.
# The `next` in each block keeps it a raw thunk.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closure-cell-fanout.XXXXXX")"

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

struct TR
  def initialize(@id : Int32)
  end

  def id : Int32
    @id
  end
end

class IV
  def initialize(@n : Int32?, @o : Int32)
  end

  def o : Int32
    @o
  end
end

class Ba
end

class Su < Ba
end

class L
  def conv(n : Int32) : TR
    TR.new(n)
  end

  def ta(t : TR, c : Bool) : Int32
    t.id &+ 4
  end

  def pick(z : Int32) : Ba
    z == 1 ? Su.new : Ba.new
  end

  def mk(n : Int32, o : Int32) : Int32
    o &+ 1
  end

  def mk(n : Nil, o : Int32) : Int32
    o &+ 2
  end

  def kd(b : Ba, o : Int32) : Int32
    o &+ 1
  end

  def kd(b : Su, o : Int32) : Int32
    o &+ 2
  end

  def mkp(n : Int32, o : Int32, f : Proc(Int32)) : Int32
    f.call
    o &+ 1
  end

  def mkp(n : Nil, o : Int32, f : Proc(Int32)) : Int32
    f.call
    o &+ 2
  end

  def kdp(b : Ba, o : Int32, f : Proc(Int32)) : Int32
    f.call
    o &+ 1
  end

  def kdp(b : Su, o : Int32, f : Proc(Int32)) : Int32
    f.call
    o &+ 2
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

# Union argument over two overloads between the write and the read.
add_case union_arg_overloads 19 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    t = z == 99 ? conv(1) : nil
    nm = z == 98 ? 5 : nil
    rep(3) do |q|
      next if q > 5
      nm = q == 1 ? nil : q
      t = conv(q)
      off = mk(nm, off)
      off = off &+ ta(t, c)
    end
    off &+ (t ? 0 : 1000) &+ (nm ? 0 : 100)
  end
end
LibC.exit(L.new.run(0, false))'

# The stage 2 shape: `.new` specialized per union argument variant.
add_case union_arg_new 18 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    t = z == 99 ? conv(1) : nil
    nm = z == 98 ? 5 : nil
    rep(3) do |q|
      next if q > 5
      nm = q == 1 ? nil : q
      t = conv(q)
      off = IV.new(nm, off).o &+ 1
      off = off &+ ta(t, c)
    end
    off &+ (t ? 0 : 1000) &+ (nm ? 0 : 100)
  end
end
LibC.exit(L.new.run(0, false))'

# Parent-class argument dispatched over a subclass overload.
add_case class_arg_overloads 19 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    t = z == 99 ? conv(1) : nil
    rep(3) do |q|
      next if q > 5
      t = conv(q)
      off = kd(pick(q), off)
      off = off &+ ta(t, c)
    end
    off &+ (t ? 0 : 1000)
  end
end
LibC.exit(L.new.run(0, false))'

# A proc nested in the writer assigns nil when the dispatched call runs it.
add_case class_arg_call_writes_reloads 106 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    t = z == 99 ? conv(1) : nil
    rep(2) do |k|
      rep(2) do |q|
        next if q > 5
        b = pick(q)
        g = -> { t = nil; 0 }
        t = conv(q &+ 1)
        # The result goes to a block local: a write to the `off` cell would
        # drop the proof by itself and hide a wrong carry across the fanout.
        r = kdp(b, off, g)
        off = r &+ ((x = t) ? x.id : 25)
      end
    end
    off
  end
end
LibC.exit(L.new.run(0, false))'

add_case union_arg_call_writes_reloads 106 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    t = z == 99 ? conv(1) : nil
    rep(2) do |k|
      rep(2) do |q|
        next if q > 5
        nm = q == 1 ? nil : q
        g = -> { t = nil; 0 }
        t = conv(q &+ 1)
        # The result goes to a block local: a write to the `off` cell would
        # drop the proof by itself and hide a wrong carry across the fanout.
        r = mkp(nm, off, g)
        off = r &+ ((x = t) ? x.id : 25)
      end
    end
    off
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
  printf '%d fanout case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all fanout cases passed\n'
