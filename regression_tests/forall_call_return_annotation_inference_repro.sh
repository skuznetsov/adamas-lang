#!/usr/bin/env bash
# A method `def skip(first : UC*, last : UC*) : UC* forall UC` included from a
# generic module was called bare (or on `self`) from another forall method.
# The AST return inference for that call (resolve_return_type_from_def)
# resolved the annotation `UC*` in the declaration's own type-parameter map,
# which never holds the call's `forall` bindings, so `p = skip(p, pend)` gave
# `p` a phantom `Pointer(UC)` and the next overloaded call failed with
# "no overload matches D.pe for argument types (Pointer(UC))". The prelude
# `"1.5".to_f64?` path stopped there (Float::FastFloat parse_mantissa →
# skip_zeros → parse_eight_digits_unrolled). The `*_control` cases already
# resolved through other paths.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forall-return-infer.XXXXXX")"

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

struct Pns(UC)
  def initialize(@ptr : Pointer(UC), @size : Int32)
  end

  def ptr : Pointer(UC)
    @ptr
  end
end

module D
  def self.pe(val : UInt64) : Int32
    val.to_i32!
  end

  def self.pe(chars : UC*) : Int32 forall UC
    pe(chars.value.to_u64!)
  end

  def self.pe(val : UInt8) : Int32
    val.to_i32! &+ 100
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

add_case implicit_self_sugar 50 '
module Bf(T, E)
  def skip(first : UC*, last : UC*) : UC* forall UC
    first + 1
  end

  def pm(num : Pns(UC)) : Int32 forall UC
    p = num.ptr
    p = skip(p, p + 3)
    D.pe(p)
  end
end

struct F64
  include Bf(Float64, UInt64)
end

buf = Pointer(UInt8).malloc(4)
buf.value = 40_u8
(buf + 1).value = 50_u8
LibC.exit(F64.new.pm(Pns.new(buf, 3)))'

add_case explicit_self 50 '
module Bf(T, E)
  def skip(first : UC*, last : UC*) : UC* forall UC
    first + 1
  end

  def pm(num : Pns(UC)) : Int32 forall UC
    p = num.ptr
    p = self.skip(p, p + 3)
    D.pe(p)
  end
end

struct F64
  include Bf(Float64, UInt64)
end

buf = Pointer(UInt8).malloc(4)
buf.value = 40_u8
(buf + 1).value = 50_u8
LibC.exit(F64.new.pm(Pns.new(buf, 3)))'

add_case pointer_spelling 50 '
module Bf(T, E)
  def skip(first : Pointer(UC), last : Pointer(UC)) : Pointer(UC) forall UC
    first + 1
  end

  def pm(num : Pns(UC)) : Int32 forall UC
    p = num.ptr
    p = skip(p, p + 3)
    D.pe(p)
  end
end

struct F64
  include Bf(Float64, UInt64)
end

buf = Pointer(UInt8).malloc(4)
buf.value = 40_u8
(buf + 1).value = 50_u8
LibC.exit(F64.new.pm(Pns.new(buf, 3)))'

add_case bare_forall_return 150 '
module Bf(T, E)
  def at(first : UC*) : UC forall UC
    first.value
  end

  def pm(num : Pns(UC)) : Int32 forall UC
    p = num.ptr + 1
    v = at(p)
    D.pe(v)
  end
end

struct F64
  include Bf(Float64, UInt64)
end

buf = Pointer(UInt8).malloc(4)
buf.value = 40_u8
(buf + 1).value = 50_u8
LibC.exit(F64.new.pm(Pns.new(buf, 3)))'

add_case module_class_method_control 50 '
module Q
  def self.skip(first : UC*, last : UC*) : UC* forall UC
    first + 1
  end
end

module Bf(T, E)
  def pm(num : Pns(UC)) : Int32 forall UC
    p = num.ptr
    p = Q.skip(p, p + 3)
    D.pe(p)
  end
end

struct F64
  include Bf(Float64, UInt64)
end

buf = Pointer(UInt8).malloc(4)
buf.value = 40_u8
(buf + 1).value = 50_u8
LibC.exit(F64.new.pm(Pns.new(buf, 3)))'

add_case toplevel_control 50 '
def skip(first : UC*, last : UC*) : UC* forall UC
  first + 1
end

def pm(num : Pns(UC)) : Int32 forall UC
  p = num.ptr
  p = skip(p, p + 3)
  D.pe(p)
end

buf = Pointer(UInt8).malloc(4)
buf.value = 40_u8
(buf + 1).value = 50_u8
LibC.exit(pm(Pns.new(buf, 3)))'

add_case concrete_receiver_control 50 '
struct Hd
  def skip(first : UC*, last : UC*) : UC* forall UC
    first + 1
  end
end

struct G(T)
  def pm(h : Hd, num : Pns(UC)) : Int32 forall UC
    p = num.ptr
    p = h.skip(p, p + 3)
    D.pe(p)
  end
end

buf = Pointer(UInt8).malloc(4)
buf.value = 40_u8
(buf + 1).value = 50_u8
LibC.exit(G(Int32).new.pm(Hd.new, Pns.new(buf, 3)))'

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
  printf '%d forall return inference case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all forall return inference cases passed\n'
