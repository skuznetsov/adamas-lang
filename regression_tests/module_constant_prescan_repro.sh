#!/usr/bin/env bash
# The constant pre-scan (cli.cr) registered constants of class bodies and of
# the top level, but not the constants a module body declares directly. A
# class registered in that module then sized an ivar by a still-unknown
# constant: `@vec = Stackvec(BIGINT_LIMBS).new` in Float::FastFloat::Bigint
# was laid out as `Stackvec(BIGINT_LIMBS)`, whose body failed with "undefined
# constant Size" (prelude `"1.5".to_f64?`). Module bodies are now pre-scanned
# too. Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-constant-prescan.XXXXXX")"

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

add_case module_constant_ivar 65 '
module FF
  LIMBS = 62

  struct Bi
    @vec = Sv(LIMBS).new

    def initialize
    end

    def get : Int32
      @vec.size
    end
  end
end

LibC.exit(FF::Bi.new.get)'

add_case module_constant_forall_pointer 7 '
module FF
  LIMBS = 62

  def self.sm(vec : Sv(Size)*) : Bool forall Size
    vec.value.size == 65
  end

  struct Bi
    @vec = Sv(LIMBS).new

    def initialize
    end

    def ok : Bool
      FF.sm(pointerof(@vec))
    end
  end
end

LibC.exit(FF::Bi.new.ok ? 7 : 3)'

add_case nested_module_constant 7 '
module A
  module B
    LIMB4 = 4

    struct C
      @v = Sv(LIMB4).new

      def initialize
      end

      def get : Int32
        @v.size
      end
    end
  end
end

LibC.exit(A::B::C.new.get)'

add_case class_constant_control 9 '
module FF
  struct Bi
    K = 6
    @vec = Sv(K).new

    def initialize
    end

    def get : Int32
      @vec.size
    end
  end
end

LibC.exit(FF::Bi.new.get)'

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
  printf '%d module constant pre-scan case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all module constant pre-scan cases passed\n'
