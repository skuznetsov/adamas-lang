#!/usr/bin/env bash
# Original-first native parity checks for named constructor overload families.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -n "$ORIGINAL" && -x "$ORIGINAL" ]] || {
  echo "candidate, installed Crystal, or SAFE runner is unavailable" >&2
  exit 2
}

if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
else
  CRYSTAL_STDLIB="$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$ORIGINAL" 10 512 env CRYSTAL_PATH)"
fi
stdlib_found=0
IFS=: read -r -a stdlib_paths <<<"$CRYSTAL_STDLIB"
for stdlib_entry in "${stdlib_paths[@]}"; do
  if [[ -d "$stdlib_entry" ]]; then
    stdlib_found=1
    break
  fi
done
[[ "$stdlib_found" == 1 ]] || { echo "installed Crystal stdlib is unavailable" >&2; exit 2; }

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-constructor-family.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache.*
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/time_span_shape.cr" <<'CRYSTAL'
lib NamedConstructorFamilyC
  fun putchar(value : Int32) : Int32
end

module Time
  struct Span
    @seconds : Int32
    @nanoseconds : Int32

    def initialize(*, seconds : Int32, nanoseconds : Int32)
      @seconds = seconds
      @nanoseconds = nanoseconds
      NamedConstructorFamilyC.putchar(73) # I
    end

    def self.new(*, nanoseconds : Int32)
      new(seconds: 0, nanoseconds: nanoseconds)
    end

    def self.new(*, seconds : Int32 = 0, nanoseconds : Int32 = 0)
      new(seconds: seconds, nanoseconds: nanoseconds)
    end
  end
end

Time::Span.new(nanoseconds: 65)
Time::Span.new(seconds: 66)
CRYSTAL
printf 'II' >"$WORK_DIR/time_span_shape.expected"

cat >"$WORK_DIR/incomparable_required_names.cr" <<'CRYSTAL'
lib NamedConstructorFamilyC
  fun putchar(value : Int32) : Int32
end

class NamedConstructorInitFirst
  def initialize(*, seconds : Int32, nanoseconds : Int32)
    NamedConstructorFamilyC.putchar(73) # I
  end

  def self.new(*, days : Int32, ticks : Int32) : Int32
    NamedConstructorFamilyC.putchar(70) # F
    days
  end
end

class NamedConstructorFactoryFirst
  def self.new(*, days : Int32, ticks : Int32) : Int32
    NamedConstructorFamilyC.putchar(70) # F
    days
  end

  def initialize(*, seconds : Int32, nanoseconds : Int32)
    NamedConstructorFamilyC.putchar(73) # I
  end
end

NamedConstructorInitFirst.new(seconds: 1, nanoseconds: 2)
NamedConstructorInitFirst.new(days: 3, ticks: 4)
NamedConstructorFactoryFirst.new(days: 5, ticks: 6)
NamedConstructorFactoryFirst.new(seconds: 7, nanoseconds: 8)
CRYSTAL
printf 'IFFI' >"$WORK_DIR/incomparable_required_names.expected"

cat >"$WORK_DIR/incomparable_overlapping_names.cr" <<'CRYSTAL'
lib NamedConstructorFamilyC
  fun putchar(value : Int32) : Int32
end

class NamedConstructorOverlapInitFirst
  def initialize(*, first : Int32, second : Int32 = 0)
    NamedConstructorFamilyC.putchar(73) # I
  end

  def self.new(*, first : Int32 = 0, second : Int32) : Int32
    NamedConstructorFamilyC.putchar(70) # F
    second
  end
end

class NamedConstructorOverlapFactoryFirst
  def self.new(*, first : Int32 = 0, second : Int32) : Int32
    NamedConstructorFamilyC.putchar(70) # F
    second
  end

  def initialize(*, first : Int32, second : Int32 = 0)
    NamedConstructorFamilyC.putchar(73) # I
  end
end

NamedConstructorOverlapInitFirst.new(first: 1, second: 2)
NamedConstructorOverlapFactoryFirst.new(first: 3, second: 4)
CRYSTAL
printf 'IF' >"$WORK_DIR/incomparable_overlapping_names.expected"

cat >"$WORK_DIR/macro_init_first_init.cr" <<'CRYSTAL'
macro named_constructor_family_init_first
  def initialize(*, first : Int32, second : Int32 = 0)
    NamedConstructorFamilyC.putchar(73) # I
  end
end

class NamedConstructorMacroInitFirst
  named_constructor_family_init_first
end
CRYSTAL

cat >"$WORK_DIR/macro_init_first_factory.cr" <<'CRYSTAL'
class NamedConstructorMacroInitFirst
  def self.new(*, first : Int32 = 0, second : Int32) : Int32
    NamedConstructorFamilyC.putchar(70) # F
    second
  end
end
CRYSTAL

cat >"$WORK_DIR/macro_init_first.cr" <<'CRYSTAL'
lib NamedConstructorFamilyC
  fun putchar(value : Int32) : Int32
end

require "./macro_init_first_init"
require "./macro_init_first_factory"

NamedConstructorMacroInitFirst.new(first: 1, second: 2)
CRYSTAL
printf 'I' >"$WORK_DIR/macro_init_first.expected"

cat >"$WORK_DIR/macro_factory_first_factory.cr" <<'CRYSTAL'
class NamedConstructorMacroFactoryFirst
  def self.new(*, first : Int32 = 0, second : Int32) : Int32
    NamedConstructorFamilyC.putchar(70) # F
    second
  end
end
CRYSTAL

cat >"$WORK_DIR/macro_factory_first_init.cr" <<'CRYSTAL'
macro named_constructor_family_init_second
  def initialize(*, first : Int32, second : Int32 = 0)
    NamedConstructorFamilyC.putchar(73) # I
  end
end

class NamedConstructorMacroFactoryFirst
  named_constructor_family_init_second
end
CRYSTAL

cat >"$WORK_DIR/macro_factory_first.cr" <<'CRYSTAL'
lib NamedConstructorFamilyC
  fun putchar(value : Int32) : Int32
end

require "./macro_factory_first_factory"
require "./macro_factory_first_init"

NamedConstructorMacroFactoryFirst.new(first: 3, second: 4)
CRYSTAL
printf 'F' >"$WORK_DIR/macro_factory_first.expected"

cat >"$WORK_DIR/equal_signature_declaration_order.cr" <<'CRYSTAL'
lib NamedConstructorFamilyC
  fun putchar(value : Int32) : Int32
end

class NamedConstructorExplicitLast
  def initialize(*, value : Int32)
    NamedConstructorFamilyC.putchar(73) # I
  end

  def self.new(*, value : Int32) : Int32
    NamedConstructorFamilyC.putchar(69) # E
    value
  end
end

class NamedConstructorInitializeLast
  def self.new(*, value : Int32) : Int32
    NamedConstructorFamilyC.putchar(69) # E
    value
  end

  def initialize(*, value : Int32)
    NamedConstructorFamilyC.putchar(73) # I
  end
end

NamedConstructorExplicitLast.new(value: 65)
NamedConstructorInitializeLast.new(value: 66)
CRYSTAL
printf 'EI' >"$WORK_DIR/equal_signature_declaration_order.expected"

cat >"$WORK_DIR/typed_and_warm_order.cr" <<'CRYSTAL'
lib NamedConstructorFamilyC
  fun putchar(value : Int32) : Int32
end

class NamedConstructorWarmFactoryFirst
  def initialize(*, value : Int32, enabled : Bool? = nil)
    NamedConstructorFamilyC.putchar(73) # I
  end

  def self.new(*, value : Bool) : Int32
    NamedConstructorFamilyC.putchar(70) # F
    value ? 1 : 0
  end
end

class NamedConstructorWarmInitializeFirst
  def self.new(*, value : Bool) : Int32
    NamedConstructorFamilyC.putchar(70) # F
    value ? 1 : 0
  end

  def initialize(*, value : Int32, enabled : Bool? = nil)
    NamedConstructorFamilyC.putchar(73) # I
  end
end

NamedConstructorWarmFactoryFirst.new(value: true)
NamedConstructorWarmFactoryFirst.new(value: 65)
NamedConstructorWarmFactoryFirst.new(value: false)
NamedConstructorWarmFactoryFirst.new(value: 66, enabled: nil)

NamedConstructorWarmInitializeFirst.new(value: 67)
NamedConstructorWarmInitializeFirst.new(value: true)
NamedConstructorWarmInitializeFirst.new(value: 68, enabled: nil)
NamedConstructorWarmInitializeFirst.new(value: false)
CRYSTAL
printf 'FIFIIFIF' >"$WORK_DIR/typed_and_warm_order.expected"

cat >"$WORK_DIR/named_and_positional_initialize.cr" <<'CRYSTAL'
lib NamedConstructorFamilyC
  fun putchar(value : Int32) : Int32
end

class NamedConstructorNamedFirst
  def initialize(*, at_end value : Int32 = 65)
    NamedConstructorFamilyC.putchar(78) # N
  end

  def initialize(value : Int32)
    NamedConstructorFamilyC.putchar(80) # P
  end
end

class NamedConstructorPositionalFirst
  def initialize(value : Int32)
    NamedConstructorFamilyC.putchar(80) # P
  end

  def initialize(*, at_end value : Int32 = 65)
    NamedConstructorFamilyC.putchar(78) # N
  end
end

NamedConstructorNamedFirst.new(at_end: 65)
NamedConstructorNamedFirst.new(66)
NamedConstructorPositionalFirst.new(67)
NamedConstructorPositionalFirst.new(at_end: 68)
CRYSTAL
printf 'NPPN' >"$WORK_DIR/named_and_positional_initialize.expected"

cat >"$WORK_DIR/included_initializer_origin.cr" <<'CRYSTAL'
lib NamedConstructorFamilyC
  fun putchar(value : Int32) : Int32
end

module NamedConstructorIncludedInitializer
  def initialize(*, first : Int32, second : Int32 = 0)
    NamedConstructorFamilyC.putchar(73) # I
  end
end

class NamedConstructorIncludeFirst
  include NamedConstructorIncludedInitializer

  def self.new(*, first : Int32 = 0, second : Int32) : Int32
    NamedConstructorFamilyC.putchar(70) # F
    second
  end
end

class NamedConstructorIncludeLast
  def self.new(*, first : Int32 = 0, second : Int32) : Int32
    NamedConstructorFamilyC.putchar(70)
    second
  end

  include NamedConstructorIncludedInitializer
end

class NamedConstructorIncludeOnly
  include NamedConstructorIncludedInitializer
end

class NamedConstructorOwnInitializer
  include NamedConstructorIncludedInitializer

  def initialize(*, first : Int32, second : Int32 = 0)
    NamedConstructorFamilyC.putchar(67) # C
  end

  def self.new(*, first : Int32 = 0, second : Int32) : Int32
    NamedConstructorFamilyC.putchar(70)
    second
  end
end

NamedConstructorIncludeFirst.new(first: 1, second: 2)
NamedConstructorIncludeLast.new(first: 1, second: 2)
NamedConstructorIncludeOnly.new(first: 1, second: 2)
NamedConstructorOwnInitializer.new(first: 1, second: 2)
CRYSTAL
printf 'FFIC' >"$WORK_DIR/included_initializer_origin.expected"

fixture_names=(
  time_span_shape
  incomparable_required_names
  incomparable_overlapping_names
  macro_init_first
  macro_factory_first
  equal_signature_declaration_order
  typed_and_warm_order
  named_and_positional_initialize
  included_initializer_origin
)

ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)

compile_case() {
  local stage="$1" name="$2"
  local -a command
  if [[ "$stage" == original ]]; then
    command=("$ORIGINAL" 180 8192 build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}")
  else
    command=("$COMPILER" 180 8192 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$name" ADAMAS_LLVM_CACHE=0 \
    "$SAFE_RUNNER" "${command[@]}" "$WORK_DIR/$name.cr" -o "$WORK_DIR/$stage.$name.bin" \
    >"$WORK_DIR/$stage.$name.compile.log" 2>&1
}

run_case() {
  local stage="$1" name="$2"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/$stage.$name.bin" 10 512 \
    >"$WORK_DIR/$stage.$name.stdout" 2>"$WORK_DIR/$stage.$name.run.log"; then
    cat "$WORK_DIR/$stage.$name.run.log" >&2
    echo "FAIL[$stage/$name]: native run failed" >&2
    return 1
  fi
  if ! grep -Fq '[EXIT: 0]' "$WORK_DIR/$stage.$name.run.log"; then
    cat "$WORK_DIR/$stage.$name.run.log" >&2
    echo "FAIL[$stage/$name]: SAFE runner did not report exit 0" >&2
    return 1
  fi
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$stage.$name.stdout"
}

check_stage() {
  local stage="$1" name
  for name in "${fixture_names[@]}"; do
    if ! compile_case "$stage" "$name"; then
      cat "$WORK_DIR/$stage.$name.compile.log" >&2
      echo "FAIL[$stage/$name]: expected successful constructor-family compilation" >&2
      return 1
    fi
    run_case "$stage" "$name"
  done
}

# Keep the installed compiler as the semantic gate before checking the candidate.
check_stage original
check_stage candidate

for name in "${fixture_names[@]}"; do
  diff -u "$WORK_DIR/original.$name.stdout" "$WORK_DIR/candidate.$name.stdout"
done

echo "PASS: named constructor selection, declaration order, typed overloads, and warm allocator-family order match installed Crystal"
