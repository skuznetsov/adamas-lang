#!/usr/bin/env bash
# Original-first contract checks for source-level class calls with literal blocks.
# Cold-cache HIR coverage lives in spec/hir/source_block_call_shape_spec.cr.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/source-block-call-admission.XXXXXX")"
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

cat >"$WORK_DIR/positive.cr" <<'CRYSTAL'
@[Link("c")]
lib SourceBlockCallAdmissionC
  fun putchar(value : Int32) : Int32
end

macro class_getter(*names)
  {% for name in names %}
    {% if name.is_a?(TypeDeclaration) %}
      {% var_name = name.var.id %}
    {% else %}
      {% var_name = name.target %}
    {% end %}
    @@{{name}}
    def self.{{var_name}} {% if name.is_a?(TypeDeclaration) %} : {{name.type}} {% end %}
      @@{{var_name}}
    end
  {% end %}
end

class SourceBlockGeneratedGetter
  alias GetterValue = Int32
  class_getter lexical_default : GetterValue = 73
  class_getter marker = 71

  def self.marker(value : Int32) : Int32
    value
  end

  def self.replace_marker(value : Int32)
    @@marker = value
  end

  def self.emit
    SourceBlockCallAdmissionC.putchar(marker)
    SourceBlockCallAdmissionC.putchar(marker())
    SourceBlockCallAdmissionC.putchar(SourceBlockGeneratedGetter.marker)
  end
end

class SourceBlockInheritedGetter < SourceBlockGeneratedGetter
  alias GetterValue = Bool
  def self.marker(value : Int32) : Int32
    value
  end
end

class SourceBlockOverriddenGetter
  class_getter marker = 71

  def self.marker : Int32
    79
  end
end

# Bare new has the same source overload family as a qualified class call.
# A named factory must not be rebound to an incompatible initialize shape.
class SourceBlockNamedFactory
  def initialize(*, seconds : Int32, nanoseconds : Int32)
  end

  def self.new(*, nanoseconds : Int32) : Int32
    nanoseconds
  end

  def self.zero : Int32
    new(nanoseconds: 70)
  end
end

# initialize contributes a separate new overload beside explicit factories.
# Its named/default ABI slots must retain that source selection.
class SourceBlockInitializerFamily
  def initialize(block : Int32? = nil, *, capacity : Int32? = nil)
    SourceBlockCallAdmissionC.putchar(74)
  end

  def self.new(default_value : Bool, capacity : Int32? = nil) : Int32
    default_value ? 84 : 85
  end

  def self.empty
    new(capacity: 0)
  end
end

class SourceBlockCallAdmission
  def self.required(value : Int32) : Int32
    SourceBlockCallAdmissionC.putchar(82)
    value
  end

  def self.defaulted(value : Int32 = 68) : Int32
    SourceBlockCallAdmissionC.putchar(value)
    value
  end

  def self.named_only(*, value : Int32) : Int32
    SourceBlockCallAdmissionC.putchar(75)
    value
  end

  def self.choose(value : Int32) : Int32
    SourceBlockCallAdmissionC.putchar(78)
    value
  end

  def self.choose(value : Int32, &block : -> Int32) : Int32
    SourceBlockCallAdmissionC.putchar(66)
    yield
  end

  def self.numeric(value : UInt8) : UInt8
    SourceBlockCallAdmissionC.putchar(85)
    value
  end

  def self.tuple_splat(first : Int32, second : Int32 = 68, &block : -> Int32) : Int32
    SourceBlockCallAdmissionC.putchar(first)
    SourceBlockCallAdmissionC.putchar(second)
    SourceBlockCallAdmissionC.putchar(yield)
  end

  def self.keyword_splat(*, first : Int32, second : Int32 = 68, &block : -> Int32) : Int32
    SourceBlockCallAdmissionC.putchar(first)
    SourceBlockCallAdmissionC.putchar(second)
    SourceBlockCallAdmissionC.putchar(yield)
  end

  def self.run
    required(1)
    SourceBlockCallAdmission.required(2)
    defaulted
    SourceBlockCallAdmission.defaulted(100)
    named_only(value: 4)
    SourceBlockCallAdmission.named_only(value: 5)
    choose(6)
    choose(7) { 8 }
    SourceBlockCallAdmission.choose(9)
    SourceBlockCallAdmission.choose(10) { 11 }
    numeric(65)
    SourceBlockCallAdmission.numeric(65)
    tuple_splat(*{65}) { 66 }
    keyword_splat(**{first: 65}) { 66 }
    SourceBlockGeneratedGetter.emit
    SourceBlockCallAdmissionC.putchar(SourceBlockInheritedGetter.marker)
    SourceBlockGeneratedGetter.replace_marker(72)
    SourceBlockCallAdmissionC.putchar(SourceBlockInheritedGetter.marker())
    SourceBlockCallAdmissionC.putchar(SourceBlockGeneratedGetter.marker())
    SourceBlockCallAdmissionC.putchar(SourceBlockInheritedGetter.marker(81))
    SourceBlockCallAdmissionC.putchar(SourceBlockGeneratedGetter.marker(82))
    SourceBlockCallAdmissionC.putchar(SourceBlockOverriddenGetter.marker())
    SourceBlockCallAdmissionC.putchar(SourceBlockInheritedGetter.lexical_default)
    SourceBlockCallAdmissionC.putchar(SourceBlockNamedFactory.zero)
    SourceBlockInitializerFamily.empty
    SourceBlockCallAdmissionC.putchar(SourceBlockInitializerFamily.new(true))
    SourceBlockCallAdmissionC.putchar(10)
  end
end

SourceBlockCallAdmission.run
CRYSTAL
printf 'RRDdKKNBNBUUADBADBGGGGGHQROIFJT\n' >"$WORK_DIR/positive.expected"

cat >"$WORK_DIR/bare_missing_required.cr" <<'CRYSTAL'
class SourceBlockBareMissingRequired
  def self.needs_argument(value : Int32, &block : -> Int32) : Int32
    yield
  end

  def self.run
    needs_argument { 65 }
  end
end

SourceBlockBareMissingRequired.run
CRYSTAL

cat >"$WORK_DIR/explicit_missing_required.cr" <<'CRYSTAL'
class SourceBlockExplicitMissingRequired
  def self.needs_argument(value : Int32, &block : -> Int32) : Int32
    yield
  end

  def self.run
    SourceBlockExplicitMissingRequired.needs_argument { 65 }
  end
end

SourceBlockExplicitMissingRequired.run
CRYSTAL

cat >"$WORK_DIR/bare_extra_argument.cr" <<'CRYSTAL'
class SourceBlockBareExtraArgument
  def self.one(value : Int32) : Int32
    value
  end

  def self.run
    one(1, 2)
  end
end

SourceBlockBareExtraArgument.run
CRYSTAL

cat >"$WORK_DIR/explicit_extra_argument.cr" <<'CRYSTAL'
class SourceBlockExplicitExtraArgument
  def self.one(value : Int32) : Int32
    value
  end

  def self.run
    SourceBlockExplicitExtraArgument.one(1, 2)
  end
end

SourceBlockExplicitExtraArgument.run
CRYSTAL

cat >"$WORK_DIR/bare_missing_block.cr" <<'CRYSTAL'
class SourceBlockBareMissingBlock
  def self.needs_block(value : Int32, &block : -> Int32) : Int32
    yield
  end

  def self.run
    needs_block(1)
  end
end

SourceBlockBareMissingBlock.run
CRYSTAL

cat >"$WORK_DIR/explicit_extra_block.cr" <<'CRYSTAL'
class SourceBlockExplicitExtraBlock
  def self.no_block(value : Int32) : Int32
    value
  end

  def self.run
    SourceBlockExplicitExtraBlock.no_block(1) { 65 }
  end
end

SourceBlockExplicitExtraBlock.run
CRYSTAL

cat >"$WORK_DIR/missing_named_only.cr" <<'CRYSTAL'
class SourceBlockMissingNamedOnly
  def self.named_only(*, value : Int32) : Int32
    value
  end

  def self.run
    named_only
  end
end

SourceBlockMissingNamedOnly.run
CRYSTAL

cat >"$WORK_DIR/positional_to_named_only.cr" <<'CRYSTAL'
class SourceBlockPositionalToNamedOnly
  def self.named_only(*, value : Int32) : Int32
    value
  end

  def self.run
    SourceBlockPositionalToNamedOnly.named_only(65)
  end
end

SourceBlockPositionalToNamedOnly.run
CRYSTAL

cat >"$WORK_DIR/missing_second_before_named_only.cr" <<'CRYSTAL'
class SourceBlockMissingSecondBeforeNamedOnly
  def self.required_pair(first : Int32, second : Int32, *, note : Int32, &block : -> Int32) : Int32
    yield
  end

  def self.run
    required_pair(1, note: 2) { 65 }
  end
end

SourceBlockMissingSecondBeforeNamedOnly.run
CRYSTAL

cat >"$WORK_DIR/initializer_wrong_named_type.cr" <<'CRYSTAL'
class SourceBlockRejectedInitializer
  def initialize(block : Int32? = nil, *, capacity : Int32? = nil)
  end

  def self.new(default_value : Bool, capacity : Int32? = nil) : Int32
    84
  end
end

SourceBlockRejectedInitializer.new(capacity: "wrong")
CRYSTAL

# The compiler represents built-in class accessors separately from DefNode.
# Their known zero-argument signature must survive strict source admission.
for getter_case in getter_extra_argument getter_extra_block; do
  cat >"$WORK_DIR/$getter_case.cr" <<'CRYSTAL'
macro class_getter(*names)
  {% for name in names %}
    {% if name.is_a?(TypeDeclaration) %}
      {% var_name = name.var.id %}
    {% else %}
      {% var_name = name.target %}
    {% end %}
    @@{{name}}
    def self.{{var_name}} {% if name.is_a?(TypeDeclaration) %} : {{name.type}} {% end %}
      @@{{var_name}}
    end
  {% end %}
end

class SourceBlockRejectedGetter
  class_getter marker = 71

  def self.run
CRYSTAL
  if [[ "$getter_case" == getter_extra_argument ]]; then
    printf '    marker(1)\n' >>"$WORK_DIR/$getter_case.cr"
  else
    printf '    marker { 1 }\n' >>"$WORK_DIR/$getter_case.cr"
  fi
  cat >>"$WORK_DIR/$getter_case.cr" <<'CRYSTAL'
  end
end

SourceBlockRejectedGetter.run
CRYSTAL
done

ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)

compile_case() {
  local stage="$1" name="$2" status=0
  local -a command
  if [[ "$stage" == original ]]; then
    command=("$ORIGINAL" 180 8192 build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}")
  else
    command=("$COMPILER" 180 8192 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$name" ADAMAS_LLVM_CACHE=0 \
    "$SAFE_RUNNER" "${command[@]}" "$WORK_DIR/$name.cr" -o "$WORK_DIR/$stage.$name.bin" \
    >"$WORK_DIR/$stage.$name.compile.log" 2>&1 || status=$?
  return "$status"
}

check_positive() {
  local stage="$1" status=0
  compile_case "$stage" positive || {
    cat "$WORK_DIR/$stage.positive.compile.log" >&2
    echo "FAIL[$stage/positive]: expected successful source call compilation" >&2
    return 1
  }
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/$stage.positive.bin" 10 512 \
    >"$WORK_DIR/$stage.stdout" 2>"$WORK_DIR/$stage.run.log" || {
      cat "$WORK_DIR/$stage.run.log" >&2
      echo "FAIL[$stage/positive]: runtime failed" >&2
      return 1
    }
  diff -u "$WORK_DIR/positive.expected" "$WORK_DIR/$stage.stdout"
}

check_rejection() {
  local stage="$1" name="$2" expected_name="$3" status=0
  compile_case "$stage" "$name" || status=$?
  if [[ "$status" != 1 || -e "$WORK_DIR/$stage.$name.bin" ]]; then
    cat "$WORK_DIR/$stage.$name.compile.log" >&2
    echo "FAIL[$stage/$name]: expected semantic rejection without an executable" >&2
    return 1
  fi
  python3 - "$WORK_DIR/$stage.$name.compile.log" "$expected_name" <<'PY_REJECT'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(errors="replace").lower()
assert "error" in text, text
assert sys.argv[2].lower() in text, text
for forbidden in ("syntax error", "parser errors", "internal compiler error", "unhandled exception"):
    assert forbidden not in text, text
PY_REJECT
}

negative_cases=(
  "bare_missing_required:needs_argument"
  "explicit_missing_required:needs_argument"
  "bare_extra_argument:one"
  "explicit_extra_argument:one"
  "bare_missing_block:needs_block"
  "explicit_extra_block:no_block"
  "missing_named_only:named_only"
  "positional_to_named_only:named_only"
  "missing_second_before_named_only:required_pair"
  "getter_extra_argument:marker"
  "getter_extra_block:marker"
  "initializer_wrong_named_type:SourceBlockRejectedInitializer"
)

# Gate the candidate on every original case first.
check_positive original
for item in "${negative_cases[@]}"; do
  check_rejection original "${item%%:*}" "${item#*:}"
done

check_positive candidate
for item in "${negative_cases[@]}"; do
  check_rejection candidate "${item%%:*}" "${item#*:}"
done

diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"
echo "PASS: source class-call arity, defaults, named-only arguments, block overloads, and literal numeric conversion"
