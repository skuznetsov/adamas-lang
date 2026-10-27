#!/usr/bin/env bash
# A capture written only inside a raw block nested in another raw block thunk
# lives in the outer thunk's closure cell. Because a nested closure writes it,
# the outer thunk drops the write proof at every call, and the nested block's
# own code used the same rule: `t = conv(q); x = t.ne0; ta(t, c)` reloaded `t`
# from the cell as `Nil | TR` after the `ne0` call. Stage 2 stopped with
# "no overload matches Adamas::HIR::AstToHir#field_storage_size for argument
# types (Nil | Adamas::HIR::TypeRef, Bool)".
# When that block is the capture's only nested writer and no closure inside it
# assigns the capture, its own body now keeps the proof across calls like the
# owning thunk does. The negative cases keep the reload when a closure nested
# in the writer, or a second nested writer, assigns the capture.
# The `next` in each inner block keeps it a raw thunk.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closure-cell-sole-writer.XXXXXX")"

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

class TR
  def initialize(@id : Int32)
  end

  def id : Int32
    @id
  end

  def ne0 : Bool
    @id != 0
  end
end

class L
  def conv(n : Int32) : TR
    TR.new(n)
  end

  def ta(t : TR, c : Bool) : Int32
    t.id &+ 4
  end

  def callp(f : Proc(Int32)) : Int32
    f.call
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

# The stage 2 shape: the inner block writes, calls a method, then reads.
add_case write_call_read 18 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    t = z == 99 ? conv(1) : nil
    rep(2) do |k|
      rep(2) do |q|
        next if q > 5
        t = conv(q)
        x = t.ne0
        off = off &+ ta(t, c)
      end
    end
    off &+ (t ? 0 : 1000)
  end
end
LibC.exit(L.new.run(0, false))'

# Three levels: the writer is nested two thunks deep.
add_case three_levels 36 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    t = z == 99 ? conv(1) : nil
    rep(2) do |j|
      rep(2) do |k|
        next if k > 5
        rep(2) do |q|
          next if q > 5
          t = conv(q)
          x = t.ne0
          off = off &+ ta(t, c)
        end
      end
    end
    off &+ (t ? 0 : 1000)
  end
end
LibC.exit(L.new.run(0, false))'

# A block nested in the writer assigns nil during a later call.
add_case nested_in_writer_reloads 100 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    t = z == 99 ? conv(1) : nil
    rep(2) do |k|
      rep(2) do |q|
        next if q > 5
        t = conv(q &+ 1)
        rep(1) do |i|
          next if i > 5
          t = nil
        end
        off = off &+ ((x = t) ? x.id : 25)
      end
    end
    off
  end
end
LibC.exit(L.new.run(0, false))'

# A proc literal in the writer assigns nil when a later call runs it.
add_case proc_in_writer_reloads 100 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    t = z == 99 ? conv(1) : nil
    rep(2) do |k|
      rep(2) do |q|
        next if q > 5
        f = -> { t = nil; 0 }
        t = conv(q &+ 1)
        callp(f)
        off = off &+ ((x = t) ? x.id : 25)
      end
    end
    off
  end
end
LibC.exit(L.new.run(0, false))'

# Two sibling blocks write the capture: neither keeps the proof.
add_case two_writers 18 '
class L
  def run(z : Int32, c : Bool) : Int32
    off = 0
    t = z == 99 ? conv(1) : nil
    rep(2) do |k|
      rep(1) do |q|
        next if q > 5
        t = conv(q &+ 2)
        x = t.ne0
        off = off &+ ((y = t) ? y.id : 50)
      end
      rep(1) do |q|
        next if q > 5
        t = q > 7 ? conv(1) : nil
      end
      off = off &+ ((w = t) ? w.id : 7)
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
  printf '%d sole nested writer case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all sole nested writer cases passed\n'
