#!/usr/bin/env bash
# `record FromCharsResultT(UC)` registers `Pointer(UC)` for its own `UC`.
# A method `def f(first : UC*, last : UC*) : FromCharsResultT(UC) forall UC`
# then resolved its parameter annotations before binding its `forall UC`
# from the call, so `UC*` found that phantom `Pointer(UC)` and the call's
# `Pointer(UInt8)` lost. `FromCharsResultT(UC).new(last, ec)` became
# `Res(UInt8).new(Pointer(UC), ...)`. Stage 2 stopped on
# Float::FastFloat parse_infnan / from_chars_advanced with "cannot safely
# lower heterogeneous returns for unsupported concrete generic receiver union
# Float::FastFloat::FromCharsResultT(UC) | Float::FastFloat::FromCharsResultT(UInt8)#ptr".
# lower_def, lower_method and lower_module_method now bind `forall` variables
# before resolving parameter annotations. The `renamed_struct_param` case is
# a control without the name collision.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forall-param-shadow.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" param="$2" body="$3"
  {
    cat <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

HEAD
    printf 'struct Res(%s)\n  def initialize(@ptr : Pointer(%s), @ec : Int32)\n  end\n\n' "$param" "$param"
    printf '  def ptr : Pointer(%s)\n    @ptr\n  end\n\n  def ec : Int32\n    @ec\n  end\nend\n' "$param"
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

# name:expected-exit
CASES=()

add_case() {
  CASES+=("$1:$2")
  write_case "$1" "$3" "$4"
}

RUN_ONE='
def run : Int32
  buf = Pointer(UInt8).malloc(4)
  r = CALL
  (r.ptr.address &- buf.address).to_i32! &* 10 &+ r.ec
end
LibC.exit(run)'

add_case toplevel_def 37 UC "
def inf(first : UC*, last : UC*) : Res(UC) forall UC
  Res(UC).new(last, 7)
end
${RUN_ONE/CALL/inf(buf, buf + 3)}"

add_case module_class_method 37 UC "
module D
  def self.inf(first : UC*, last : UC*) forall UC
    Res(UC).new(last, 7)
  end
end
${RUN_ONE/CALL/D.inf(buf, buf + 3)}"

add_case generic_instance_method 37 UC "
module D
  def self.inf(first : UC*, last : UC*, value : T*) : Res(UC) forall T, UC
    Res(UC).new(last, 7)
  end
end

struct Fmt(T)
  def adv(first : UC*, last : UC*, value : T*) : Res(UC) forall UC
    D.inf(first, last, value)
  end
end

def run : Int32
  buf = Pointer(UInt8).malloc(4)
  v = 0.0
  r = Fmt(Float64).new.adv(buf, buf + 3, pointerof(v))
  (r.ptr.address &- buf.address).to_i32! &* 10 &+ r.ec
end
LibC.exit(run)"

add_case fast_float_shape 75 UC "
module D
  def self.inf(first : UC*, last : UC*, value : T*) : Res(UC) forall T, UC
    Res(UC).new(last, 7)
  end
end

struct Fmt(T)
  def adv(first : UC*, last : UC*, value : T*, k : Int32) : Res(UC) forall UC
    if k == 0
      return Res(UC).new(first, 3)
    end
    if k == 1
      return D.inf(first, last, value)
    end
    Res(UC).new(last, 5)
  end
end

def run(k : Int32) : Int32
  buf = Pointer(UInt8).malloc(4)
  v = 0.0
  r = Fmt(Float64).new.adv(buf, buf + 3, pointerof(v), k)
  (r.ptr.address &- buf.address).to_i32! &* 10 &+ r.ec
end
LibC.exit(run(0) &+ run(1) &+ run(2))"

add_case renamed_struct_param 37 Q "
def inf(first : UC*, last : UC*) : Res(UC) forall UC
  Res(UC).new(last, 7)
end
${RUN_ONE/CALL/inf(buf, buf + 3)}"

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
  printf '%d forall parameter case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all forall parameter cases passed\n'
