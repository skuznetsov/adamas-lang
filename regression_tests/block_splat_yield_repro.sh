#!/usr/bin/env bash
# Inline yield bound block parameters strictly by position and ignored both
# splat forms: `yield *args` passed the tuple as one argument, and a block
# splat parameter (`|*args|`) received only the first yielded value. The
# common forwarding shape `each_v2 { |*args| yield *args }` therefore left
# every block parameter after the first unbound; the 1.22.1 prelude's
# Crystal::DWARF file_and_directory_at failed with "undefined method
# 'dir_index'" (older builds silently read garbage). Each case exits 42 under
# original Crystal, which also keeps a single yielded tuple whole when the
# block has a splat parameter.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block-splat-yield.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/forward_destructure.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

class Seq
  def each_file(&) : Nil
    each_v2 { |*args| yield *args }
  end

  private def each_v2(&)
    path = {7, 8}
    yield path, 27, 0, 0, nil
  end
end

def pick(seq)
  r = 0
  seq.each_file do |(form, value), dir_index, _, _, _|
    r = dir_index + form + value
  end
  r
end

LibC.exit(pick(Seq.new))
CR

cat > "$WORK_DIR/forward_scalar.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

class Seq
  def each_file(&) : Nil
    each_v2 { |*args| yield *args }
  end

  private def each_v2(&)
        yield 15, 27
  end
end

def pick(seq)
  r = 0
  seq.each_file do |form, dir_index|
    r = dir_index + form
  end
  r
end

LibC.exit(pick(Seq.new))
CR

cat > "$WORK_DIR/splat_param_direct.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

class Seq
  def each_v2(&)
    yield 15, 27
  end
end

r = 0
Seq.new.each_v2 { |*args| r = args[1] + args[0] }
LibC.exit(r)
CR

cat > "$WORK_DIR/middle_splat.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

def y1(&)
  yield 10, 5, 27
end

r = 0
y1 { |a, *b, c| r = a + b[0] + c }
LibC.exit(r)
CR

cat > "$WORK_DIR/single_tuple_into_splat.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

def y1(&)
  yield({15, 27})
end

r = 0
y1 { |*args| r = args[0][0] + args[0][1] }
LibC.exit(r)
CR

cat > "$WORK_DIR/empty_splat.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

def y1(&)
  yield 42
end

r = 0
y1 { |a, *b| r = a }
LibC.exit(r)
CR

CASES=(
  "forward_destructure:42"
  "forward_scalar:42"
  "splat_param_direct:42"
  "middle_splat:42"
  "single_tuple_into_splat:42"
  "empty_splat:42"
)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d block splat yield case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'block splat yield cases passed\n'
