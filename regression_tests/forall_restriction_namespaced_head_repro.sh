#!/usr/bin/env bash
# `def self.small_mul(vec : Stackvec(Size)*, y : Limb) : Bool forall Size`
# is declared inside `module Float::FastFloat`, so its restriction spells the
# generic head unqualified while the argument type is canonical
# (`Pointer(Float::FastFloat::Stackvec(62))`). The forall binder compared the
# heads as strings (`Stackvec` vs `Float::FastFloat::Stackvec`), left `Size`
# unbound, and the overload check rejected the call: "no overload matches
# Float::FastFloat.small_mul for argument types (Pointer(...Stackvec(62)),
# UInt64)" on the prelude `"1.5".to_f64?` path. Heads are now resolved in the
# declaration scope. `qualified_head_control` already passed; the rooted cases check
# that a `::Sv(Size)` restriction still binds only the top-level type.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forall-namespaced-head.XXXXXX")"

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

struct Sv(Size)
  def initialize
  end

  def size : Int32
    Size
  end
end

module FF
  alias Limb = UInt64

  struct Sv(Size)
    def initialize
      @len = 3
    end

    def size : Int32
      @len &+ Size
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

add_case nested_pointer 65 '
module FF
  def self.sm(vec : Sv(Size)*) : Int32 forall Size
    vec.value.size
  end
end

v = FF::Sv(62).new
LibC.exit(FF.sm(pointerof(v)))'

add_case nested_value 65 '
module FF
  def self.sm(vec : Sv(Size)) : Int32 forall Size
    vec.size
  end
end

LibC.exit(FF.sm(FF::Sv(62).new))'

add_case nested_pointer_generic 65 '
module FF
  def self.sm(vec : Pointer(Sv(Size))) : Int32 forall Size
    vec.value.size
  end
end

v = FF::Sv(62).new
LibC.exit(FF.sm(pointerof(v)))'

add_case ivar_pointer_alias_arg 7 '
module FF
  def self.sm(vec : Sv(Size)*, y : Limb) : Bool forall Size
    vec.value.size == 65 && y == 2_u64
  end

  struct Bi
    @vec = Sv(62).new

    def initialize
    end

    def mul(y : Limb) : Bool
      FF.sm(pointerof(@vec), y)
    end
  end
end

LibC.exit(FF::Bi.new.mul(2_u64) ? 7 : 3)'

add_case rooted_head 7 '
module FF
  def self.sm(vec : ::Sv(Size)) : Int32 forall Size
    vec.size &+ 2
  end
end

LibC.exit(FF.sm(::Sv(5).new))'

add_case qualified_head_control 65 '
module FF
  def self.sm(vec : FF::Sv(Size)*) : Int32 forall Size
    vec.value.size
  end
end

v = FF::Sv(62).new
LibC.exit(FF.sm(pointerof(v)))'

add_case rooted_and_toplevel_pointer_heads 9 '
module FF
  def self.top(vec : ::Sv(Size)*) : Int32 forall Size
    vec.value.size
  end
end

module G
  def self.sm(vec : Sv(Size)*) : Int32 forall Size
    vec.value.size
  end
end

v = Sv(4).new
LibC.exit(G.sm(pointerof(v)) &+ FF.top(pointerof(v)) &+ 1)'

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
  printf '%d forall namespaced-head case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all forall namespaced-head cases passed\n'
