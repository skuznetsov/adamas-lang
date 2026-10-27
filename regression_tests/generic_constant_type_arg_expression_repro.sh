#!/usr/bin/env bash
# A numeric constant as a generic argument in a type expression
# (`Stackvec(BIGINT_LIMBS).new`, `t = Sv(N)`) denotes the constant's value, as
# it already did in annotations (resolve_generic_type_param_name). The
# expression paths (lower_member_access, lower_generic_type_ref) kept the
# spelling, instantiated `Sv(N)`, and the body's `Size` then failed with
# "undefined constant Size" (or crashed in a module method). The control
# checks that an enclosing generic's own type parameter `N` still wins over a
# same-named constant. Each case exits with its expected code under original
# Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-constant-arg.XXXXXX")"

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
    @len = 3
  end

  def size : Int32
    @len &+ Size
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

add_case toplevel_new 65 '
N = 62
LibC.exit(Sv(N).new.size)'

add_case module_method 65 '
module FF
  N = 62

  def self.mk : Int32
    Sv(N).new.size
  end
end

LibC.exit(FF.mk)'

add_case module_ivar_default 65 '
module FF
  N = 62

  struct Bi
    @vec = Sv(N).new

    def initialize
    end

    def get : Int32
      @vec.size
    end
  end
end

LibC.exit(FF::Bi.new.get)'

add_case type_value_receiver 65 '
N = 62
t = Sv(N)
LibC.exit(t.new.size)'

add_case type_param_shadows_constant 8 '
N = 62

struct W(N)
  def initialize
  end

  def mk : Int32
    Sv(N).new.size
  end
end

LibC.exit(W(5).new.mk)'

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
  printf '%d generic constant-argument case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all generic constant-argument cases passed\n'
