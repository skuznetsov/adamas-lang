#!/usr/bin/env bash
# Crystal types a call by its body when the body is narrower than the return
# annotation: `def prim_for(name) : Ty?` whose body only yields `Prim | Nil`
# makes `prim_for(x)` a `Prim | Nil`, so `take(base : Prim)` matches after
# `return nil unless base = prim_for(x)`. V2 only narrowed the single-variant
# case (every return the same non-nil arm) and kept `Ty?` here. Stage2 failed
# in TypeInferenceEngine#infer_builtin_path_type with no overload for
# builtin_primitive_constant_type(Type, String). Each case exits with its
# expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/narrowed-union-return.XXXXXX")"

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

add_case if_chain_body_narrower_than_annotation 9 '
abstract class Ty
end

class Prim < Ty
  def initialize(@n : Int32)
  end

  def n : Int32
    @n
  end
end

class Other < Ty
end

class Ctx
  def int8 : Prim
    Prim.new(8)
  end
end

class Eng
  def initialize
    @ctx = Ctx.new
  end

  def prim_for(name : Int32) : Ty?
    if name == 1
      Prim.new(1)
    elsif name == 2
      @ctx.int8
    else
      nil
    end
  end

  def take(p : Prim, m : Int32) : Int32
    p.n &+ m
  end

  def run(name : Int32) : Int32?
    return nil unless base = prim_for(name)
    take(base, 1)
  end
end

LibC.exit(Eng.new.run(2) || 0)'

add_case callee_defined_after_caller 9 '
abstract class Ty
end

class Prim < Ty
  def initialize(@n : Int32)
  end

  def n : Int32
    @n
  end
end

class Other < Ty
end

class Ctx
  def int8 : Prim
    Prim.new(8)
  end
end

class Eng
  def initialize
    @ctx = Ctx.new
  end

  def take(p : Prim, m : Int32) : Int32
    p.n &+ m
  end

  def run(name : Int32) : Int32?
    return nil unless base = prim_for(name)
    take(base, 1)
  end

  def prim_for(name : Int32) : Ty?
    if name == 1
      Prim.new(1)
    elsif name == 2
      @ctx.int8
    else
      nil
    end
  end
end

LibC.exit(Eng.new.run(2) || 0)'

add_case early_returns_narrower_than_annotation 9 '
abstract class Ty
end

class Prim < Ty
  def initialize(@n : Int32)
  end

  def n : Int32
    @n
  end
end

class Other < Ty
end

class Ctx
  def int8 : Prim
    Prim.new(8)
  end
end

class Eng
  def initialize
    @ctx = Ctx.new
  end

  def prim_for(name : Int32) : Ty?
    return nil if name == 0
    return Prim.new(1) if name == 1
    @ctx.int8
  end

  def take(p : Prim, m : Int32) : Int32
    p.n &+ m
  end

  def run(name : Int32) : Int32?
    return nil unless base = prim_for(name)
    take(base, 1)
  end
end

LibC.exit(Eng.new.run(2) || 0)'

add_case value_union_body_narrower_than_annotation 116 '
class Box
  def initialize(@v : Int32)
  end

  def v : Int32
    @v
  end
end

class Eng
  def pick(n : Int32) : Int32 | Box | Nil
    if n == 1
      n &+ 4
    elsif n == 2
      nil
    else
      n &+ 6
    end
  end

  def take(x : Int32) : Int32
    x &+ 1
  end

  def run(n : Int32) : Int32
    if v = pick(n)
      take(v)
    else
      100
    end
  end
end

e = Eng.new
LibC.exit(e.run(1) &+ e.run(2) &+ e.run(3))'

# A body union whose Proc arm is less specific than the annotation (bare
# `Proc` against `Proc(Int32, Int32)`) is not narrower and must keep `T?`.
add_case generic_proc_arm_keeps_annotation 7 '
class Stack(T)
  def initialize(@v : T)
    @full = true
  end

  def pop(&)
    if @full
      @full = false
      @v
    else
      yield
    end
  end

  def pop? : T?
    pop { nil }
  end
end

s = Stack(Proc(Int32, Int32)).new(->(x : Int32) { x &+ 1 })
if h = s.pop?
  LibC.exit(h.call(6))
end
LibC.exit(3)'

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
  printf '%d narrowed union return case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all narrowed union return cases passed\n'
