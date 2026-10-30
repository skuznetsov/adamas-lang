#!/usr/bin/env bash
# A selected yielding Def's declared block result is a source contract. Check
# literal block completion values against it before inline-yield ABI inference
# rewrites Nil/Void, while keeping block escapes distinct from callback results.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
ONLY_CASES="${ONLY_CASES:-}"

[[ -x "$SAFE_RUNNER" && -n "$ORIGINAL" && -x "$ORIGINAL" ]] || {
  echo "SAFE runner or installed Crystal is unavailable" >&2
  exit 2
}
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
else
  CRYSTAL_STDLIB="$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$ORIGINAL" 10 256 env CRYSTAL_PATH 2>/dev/null)" || {
    echo "could not read installed Crystal's CRYSTAL_PATH" >&2
    exit 2
  }
fi
stdlib_found=0
IFS=: read -r -a stdlib_paths <<<"$CRYSTAL_STDLIB"
for stdlib_path in "${stdlib_paths[@]}"; do
  [[ -d "$stdlib_path" ]] && stdlib_found=1
done
[[ "$stdlib_found" == 1 ]] || {
  echo "installed Crystal CRYSTAL_PATH has no existing source directory: $CRYSTAL_STDLIB" >&2
  exit 2
}
if [[ "$ORIGINAL_ONLY" != 1 && ! -x "$COMPILER" ]]; then
  echo "candidate compiler is unavailable: $COMPILER" >&2
  exit 2
fi
if [[ -n "$ONLY_CASES" ]]; then
  IFS=, read -r -a selected_cases <<<"$ONLY_CASES"
  for selected_case in "${selected_cases[@]}"; do
    case "$selected_case" in
      positive|positive_class_output|positive_mixed_kind_argument|positive_nullable_output|positive_yield_discard_result|positive_method_nil_result|positive_allocator_result|positive_default_provenance|positive_owner_generic_output|positive_mixed_value_kind_source|positive_array_output_source|reject_mixed_value_kind_source|reject_array_output_shape|reject_explicit_defaulted_input|reject_wrong_normal_result|reject_anonymous_wrong_result|reject_generic_fixed_by_value|reject_receiver_owned_generic_result|reject_class_receiver_generic_result|reject_named_fixed_by_value|reject_wrong_next_result|reject_nil_fallthrough|reject_wrong_class_literal_kind|reject_nested_forwarded_result)
        ;;
      *)
        echo "unknown selected block output case: $selected_case" >&2
        exit 2
        ;;
    esac
  done
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/selected-block-output-contract.XXXXXX")"
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
lib LibC
  fun putchar(value : Int32) : Int32
end

class SelectedBlockEscape
end

class SelectedBlockClassNamespace
  class Foo
  end

  def self.class_value(&block : -> Foo.class) : Foo.class
    yield
  end

  def self.output_only(&block : -> T) : T forall T
    yield
  end

  def self.observe(value : Foo.class) : Nil
    LibC.putchar(67)
  end

  def self.run : Nil
    observe(class_value { LibC.putchar(77); Foo })
    observe(output_only { LibC.putchar(88); Foo })
  end
end

class Foo
end

class SelectedBlockOwnerGenericBox(T)
  def initialize(@value : T)
  end

  def output_only(&block : -> T) : T forall T
    yield
  end
end

class SelectedBlockOutputContract
  def self.value(&block : -> Int32) : Int32
    yield
  end

  def self.discard_nil(&block : -> Nil) : Nil
    yield
    nil
  end

  def self.discard_void(&block : ->) : Nil
    yield
    nil
  end

  def self.bound(value : T, &block : -> T) : T forall T
    yield
  end

  def self.bound_named(*, value : T, &block : -> T) : T forall T
    yield
  end

  def self.observe_string(value : String) : Nil
    LibC.putchar(79)
  end

  def self.output_only(&block : -> T) : T forall T
    yield
  end

  def self.output_only_forwarded(&block : -> T) : T forall T
    output_only { yield }
  end

  def self.observe_nil(value : Nil) : Nil
    LibC.putchar(76)
  end

  def self.abstract_int(&block : -> Int) : Int
    yield
  end

  def self.result_with_marker : Int32
    LibC.putchar(78)
    70
  end

  def self.normal_result_with_marker : Int32
    LibC.putchar(79)
    71
  end

  # The non-local return makes this a force-inline yield path. The false run
  # exercises `next` as the actual yield result, including its operand effect.
  def self.inline_next_case(flag : Bool) : Int32
    value do
      return 76 if flag
      next result_with_marker
    end
  end

  # The non-local return forces inline lowering, while use_next chooses
  # between `next` and ordinary block fallthrough at runtime.
  def self.inline_next_merge_case(use_next : Bool, return_now : Bool) : Int32
    value do
      return 76 if return_now
      if use_next
        next result_with_marker
      end
      normal_result_with_marker
    end
  end

  # The callback's `next` runs inside this yielding loop and supplies the value
  # of each yield invocation while preserving the side effect before it.
  def self.twice(&block : -> Int32) : Int32
    result = 0
    index = 0
    while index < 2
      result = yield
      index &+= 1
    end
    result
  end

  # These exits leave the callback/call site; they do not produce a callback
  # result and therefore are not constrained by SelectedBlockEscape.
  def self.escape_call(&block : -> SelectedBlockEscape) : Int32
    yield
    71
  end

  def self.nonlocal_return : Int32
    escape_call { return 82 }
    83
  end

  def self.break_result : Int32
    escape_call { break 66 }
  end
end

LibC.putchar(SelectedBlockOutputContract.value { 65 })
LibC.putchar(10)
SelectedBlockOutputContract.discard_nil { LibC.putchar(78); 65 }
SelectedBlockOutputContract.discard_void { LibC.putchar(86); 66 }
LibC.putchar(10)
LibC.putchar(SelectedBlockOutputContract.bound(0_i32) { 67_i32 })
SelectedBlockOutputContract.bound("seed") { LibC.putchar(83); "result" }
SelectedBlockOutputContract.abstract_int { 7_u64 }
LibC.putchar(SelectedBlockOutputContract.bound_named(value: 0_i32) { 74_i32 })
LibC.putchar(85)
SelectedBlockOutputContract.observe_string(
  SelectedBlockOwnerGenericBox(Int32).new(0_i32).output_only { "owner shadow" }
)
LibC.putchar(10)
LibC.putchar(SelectedBlockOutputContract.output_only { 68 })
LibC.putchar(SelectedBlockOutputContract.output_only_forwarded { 69 })
SelectedBlockOutputContract.observe_nil(SelectedBlockOutputContract.output_only { nil })
LibC.putchar(10)
SelectedBlockClassNamespace.run
LibC.putchar(10)
LibC.putchar(SelectedBlockOutputContract.twice do
  next SelectedBlockOutputContract.result_with_marker
end)
LibC.putchar(10)
LibC.putchar(SelectedBlockOutputContract.inline_next_case(false))
LibC.putchar(10)
LibC.putchar(SelectedBlockOutputContract.inline_next_merge_case(true, false))
LibC.putchar(SelectedBlockOutputContract.inline_next_merge_case(false, false))
LibC.putchar(10)
LibC.putchar(SelectedBlockOutputContract.nonlocal_return)
LibC.putchar(SelectedBlockOutputContract.break_result)
LibC.putchar(10)
CRYSTAL
printf 'A\nNV\nCSJUO\nDEL\nMCXC\nNNF\nNF\nNFOG\nRB\n' >"$WORK_DIR/positive.expected"

cat >"$WORK_DIR/positive_class_output.cr" <<'CRYSTAL'
@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end
class SourceClassOutputMarker
end
module SourceModuleOutputMarker
end
class SourceMetaclassOutput
  def self.class_value(&block : -> Class)
    yield
    LibC.putchar(67)
  end
  def self.value(&block : -> Value)
    yield
    LibC.putchar(86)
  end
  def self.object(&block : -> Object)
    yield
    LibC.putchar(79)
  end
end
SourceMetaclassOutput.class_value { SourceClassOutputMarker }
SourceMetaclassOutput.class_value { SourceModuleOutputMarker }
SourceMetaclassOutput.value { SourceClassOutputMarker }
SourceMetaclassOutput.object { SourceClassOutputMarker }
LibC.putchar(10)
CRYSTAL
printf 'CCVO\n' >"$WORK_DIR/positive_class_output.expected"

cat >"$WORK_DIR/positive_mixed_kind_argument.cr" <<'CRYSTAL'
@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end
class MixedKindArgumentMarker
end
def accept_mixed_kind(value : T, &block : -> T) forall T
  yield
  LibC.putchar(84)
end
def choose_mixed_kind(flag : Bool)
  value = if flag
    MixedKindArgumentMarker
  else
    1
  end
  accept_mixed_kind(value) do
    if flag
      MixedKindArgumentMarker
    else
      1
    end
  end
end
choose_mixed_kind(true)
choose_mixed_kind(false)
LibC.putchar(10)
CRYSTAL
printf 'TT\n' >"$WORK_DIR/positive_mixed_kind_argument.expected"

cat >"$WORK_DIR/positive_nullable_output.cr" <<'CRYSTAL'
@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end

class SelectedNullableClassResult
end

class SelectedNullableOutput
  def self.output(&block : -> T?) : T? forall T
    yield
  end

  def self.concrete_first(&block : -> Int32 | T) : T forall T
    yield
  end

  def self.observe_nil(value : Nil) : Nil
    LibC.putchar(78)
  end

  # Check callback kind directly. Ordinary overload selection between a
  # metaclass and its instance has a separate baseline bug, even without a
  # block; it must not stand in for callback-result contract validation here.
  def self.observe_class(&block : -> SelectedNullableClassResult.class) : Nil
    yield
    LibC.putchar(67)
  end
end

LibC.putchar(SelectedNullableOutput.output { 65_i32 })
LibC.putchar(10)
SelectedNullableOutput.observe_nil(SelectedNullableOutput.output { nil })
LibC.putchar(10)
SelectedNullableOutput.observe_class { SelectedNullableOutput.output { SelectedNullableClassResult } }
LibC.putchar(SelectedNullableOutput.concrete_first { 73_i32 })
LibC.putchar(10)
CRYSTAL
printf 'A\nN\nCI\n' >"$WORK_DIR/positive_nullable_output.expected"

cat >"$WORK_DIR/positive_yield_discard_result.cr" <<'CRYSTAL'
@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end

class SelectedBlockYieldDiscardResult
  def self.yield_nil(&block : -> Nil)
    yield
  end

  def self.yield_void(&block : ->)
    yield
  end

  def self.declared_nil(&block : -> Nil) : Nil
    yield
  end

  def self.call_nil(&block : -> Nil)
    block.call
  end

  def self.observe_nil(value : Nil) : Nil
    LibC.putchar(78)
  end
end

# The source callback restriction may discard a body result when adapting a
# Proc, but yield forwards the actual result until the method's own return.
LibC.putchar(SelectedBlockYieldDiscardResult.yield_nil { 65 })
LibC.putchar(SelectedBlockYieldDiscardResult.yield_void { 66 })
SelectedBlockYieldDiscardResult.observe_nil(SelectedBlockYieldDiscardResult.yield_nil { nil })
SelectedBlockYieldDiscardResult.observe_nil(SelectedBlockYieldDiscardResult.declared_nil { 67 })
SelectedBlockYieldDiscardResult.observe_nil(SelectedBlockYieldDiscardResult.call_nil { 68 })
LibC.putchar(10)
CRYSTAL
printf 'ABNNN\n' >"$WORK_DIR/positive_yield_discard_result.expected"

cat >"$WORK_DIR/positive_method_nil_result.cr" <<'CRYSTAL'
@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

# Empty-prelude codegen references these exception hooks for ensure cleanup.
# This case exercises only normal completion; any unexpected unwind exits with
# a distinct sentinel instead of being mistaken for a passing result.
fun __crystal_personality(version : Int32, actions : Int32, cls : UInt64, ex : Void*, ctx : Void*) : Int32
  LibC._exit(97)
end

fun __crystal_get_exception(ex : Void*) : UInt64
  LibC._exit(97)
end

fun __crystal_raise(ex : Void*) : NoReturn
  LibC._exit(98)
end

fun __crystal_raise_overflow : NoReturn
  LibC._exit(99)
end

class SelectedMethodNilResult
  alias DiscardResult = Nil

  def self.explicit_nil(&block : -> Int32) : Nil
    begin
      return yield
    ensure
      LibC.putchar(69)
    end
  end

  def self.completion_nil(&block : -> Int32) : Nil
    begin
      yield
    ensure
      LibC.putchar(70)
    end
  end

  def self.alias_nil(&block : -> Int32) : DiscardResult
    begin
      yield
    ensure
      LibC.putchar(71)
    end
  end

  def self.pure_yield(&block : -> Nil)
    yield
  end

  def self.nil_helper(&block : -> Int32) : Nil
    begin
      return yield
    ensure
      LibC.putchar(77)
    end
  end

  def self.return_control : Int32
    nil_helper do
      begin
        LibC.putchar(82)
        return 72_i32
      ensure
        LibC.putchar(66)
      end
    end
    0_i32
  ensure
    LibC.putchar(67)
  end

  def self.break_control : Int32
    nil_helper do
      begin
        LibC.putchar(75)
        break 73_i32
      ensure
        LibC.putchar(66)
      end
    end
  ensure
    LibC.putchar(67)
  end

  def self.observe_nil(value : Nil) : Nil
    LibC.putchar(78)
  end
end

# A method-level Nil annotation adapts both explicit returns and ordinary
# completion, while the callback's own Nil contract does not erase yield's
# actual result. A break and a nonlocal return still escape through the helper.
SelectedMethodNilResult.observe_nil(SelectedMethodNilResult.explicit_nil { LibC.putchar(88) })
SelectedMethodNilResult.observe_nil(SelectedMethodNilResult.completion_nil { LibC.putchar(89) })
SelectedMethodNilResult.observe_nil(SelectedMethodNilResult.alias_nil { LibC.putchar(90) })
LibC.putchar(SelectedMethodNilResult.pure_yield { LibC.putchar(80) })
LibC.putchar(SelectedMethodNilResult.return_control)
LibC.putchar(SelectedMethodNilResult.break_control)
LibC.putchar(10)
CRYSTAL
printf 'XENYFNZGNPPRBMCHKBMCI\n' >"$WORK_DIR/positive_method_nil_result.expected"

cat >"$WORK_DIR/positive_allocator_result.cr" <<'CRYSTAL'
@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end

class SelectedPhysicalAllocator
  def initialize(first : Nil, second : Int32, third : Bool, &@callback : ->)
  end

  def value : Int32
    65
  end
end

class SelectedForeignFactory
  def self.new(first : String, second : String, third : Nil, &block : -> Int32)
    yield
  end
end

# An arity-compatible foreign factory cannot supply the physical allocator's
# result. The captured callback finishes with Nil; the object is still returned.
LibC.putchar(SelectedPhysicalAllocator.new(nil, 1, true) { nil }.value)
# An explicitly selected source factory owns its ordinary body result.
LibC.putchar(SelectedForeignFactory.new("first", "second", nil) { 66_i32 })
LibC.putchar(10)
CRYSTAL
printf 'AB\n' >"$WORK_DIR/positive_allocator_result.expected"

cat >"$WORK_DIR/positive_default_provenance.cr" <<'CRYSTAL'
@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end

class SelectedDefaultOutputProvenance
  def self.defaulted(value : T? = nil, &block : -> T) : T forall T
    yield
  end

  def self.explicit(value : T, &block : -> T) : T forall T
    yield
  end
end

# The omitted Nil default must not bind T; the callback infers Int32.
LibC.putchar(SelectedDefaultOutputProvenance.defaulted { 66_i32 })
LibC.putchar(10)
# A source-supplied ordinary value does bind T and constrains the callback.
LibC.putchar(SelectedDefaultOutputProvenance.explicit(67_i32) { 67_i32 })
LibC.putchar(10)
CRYSTAL
printf 'B\nC\n' >"$WORK_DIR/positive_default_provenance.expected"

cat >"$WORK_DIR/positive_owner_generic_output.cr" <<'CRYSTAL'
@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end

struct SelectedBlockOwnerBox(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end

  begin
    def self.build(&block : -> T) : SelectedBlockOwnerBox(T)
      SelectedBlockOwnerBox(T).new(yield)
    end
  end

  def self.shadow(value : T, &block : -> T) : SelectedBlockOwnerBox(T) forall T
    SelectedBlockOwnerBox(T).new(yield)
  end
end

bare = SelectedBlockOwnerBox.build { 65_i32 }
explicit = SelectedBlockOwnerBox(Int32).build { 66_i32 }
shadowed = SelectedBlockOwnerBox(String).shadow(0_i32) { 67_i32 }
LibC.putchar(bare.value)
LibC.putchar(explicit.value)
LibC.putchar(shadowed.value)
LibC.putchar(10)
CRYSTAL
printf 'ABC\n' >"$WORK_DIR/positive_owner_generic_output.expected"

cat >"$WORK_DIR/reject_class_receiver_generic_result.cr" <<'CRYSTAL'
struct SelectedBlockConcreteOwner(T)
  def self.value(&block : -> T) : T
    yield
  end
end

SelectedBlockConcreteOwner(String).value { 65_i32 }
CRYSTAL

cat >"$WORK_DIR/positive_mixed_value_kind_source.cr" <<'CRYSTAL'
class SelectedInstanceResult
end

class SelectedClassResult
end

class SelectedMixedValueKind
  def self.accept(&block : -> SelectedInstanceResult | SelectedClassResult.class) : Nil
    yield
    nil
  end

  def self.merged(flag : Bool) : Nil
    accept do
      if flag
        Pointer(SelectedInstanceResult).new(0_u64).as(SelectedInstanceResult)
      else
        SelectedClassResult
      end
    end
  end

  def self.next_merged(flag : Bool, escape : Bool) : Nil
    accept do
      return nil if escape
      next Pointer(SelectedInstanceResult).new(0_u64).as(SelectedInstanceResult) if flag
      SelectedClassResult
    end
  end
end

# Typechecking only: the fake instance pointer is never dereferenced or run.
SelectedMixedValueKind.merged(false)
SelectedMixedValueKind.next_merged(false, false)
CRYSTAL

cat >"$WORK_DIR/reject_mixed_value_kind_source.cr" <<'CRYSTAL'
class SelectedInstanceResult
end

class SelectedClassResult
end

class SelectedMixedValueKind
  def self.accept(&block : -> SelectedInstanceResult | SelectedClassResult.class) : Nil
    yield
    nil
  end

  def self.merged(flag : Bool) : Nil
    accept do
      if flag
        SelectedInstanceResult
      else
        Pointer(SelectedClassResult).new(0_u64).as(SelectedClassResult)
      end
    end
  end
end

SelectedMixedValueKind.merged(false)
CRYSTAL

cat >"$WORK_DIR/positive_array_output_source.cr" <<'CRYSTAL'
class SelectedArrayOutputSource
  def self.output(&block : -> Array(T)) : Array(T) forall T
    yield
  end
end

# This is a typechecking oracle only: the pointer is never dereferenced and
# this fixture is not emitted or run as a native program.
SelectedArrayOutputSource.output { Pointer(Array(Int32)).new(0_u64).as(Array(Int32)) }
CRYSTAL

cat >"$WORK_DIR/reject_array_output_shape.cr" <<'CRYSTAL'
class SelectedArrayOutputSource
  def self.output(&block : -> Array(T)) : Array(T) forall T
    yield
  end
end

SelectedArrayOutputSource.output { "wrong" }
CRYSTAL

cat >"$WORK_DIR/reject_explicit_defaulted_input.cr" <<'CRYSTAL'
class SelectedDefaultOutputProvenance
  def self.explicit(value : T, &block : -> T) : T forall T
    yield
  end
end

SelectedDefaultOutputProvenance.explicit(0_i32) { "wrong" }
CRYSTAL

cat >"$WORK_DIR/reject_wrong_normal_result.cr" <<'CRYSTAL'
class SelectedBlockExpectedResult
end

class SelectedBlockWrongNormalResult
  def self.needs_expected(&block : -> SelectedBlockExpectedResult) : SelectedBlockExpectedResult
    yield
  end

  def self.run
    needs_expected { 65 }
  end
end

SelectedBlockWrongNormalResult.run
CRYSTAL

cat >"$WORK_DIR/reject_anonymous_wrong_result.cr" <<'CRYSTAL'
class SelectedBlockAnonymousExpected
end

class SelectedBlockAnonymousWrongResult
  def self.needs_expected(& : -> SelectedBlockAnonymousExpected) : SelectedBlockAnonymousExpected
    yield
  end

  def self.run
    needs_expected { 65 }
  end
end

SelectedBlockAnonymousWrongResult.run
CRYSTAL

cat >"$WORK_DIR/reject_generic_fixed_by_value.cr" <<'CRYSTAL'
class SelectedBlockGenericFixedMismatch
  def self.bound(value : T, &block : -> T) : T forall T
    yield
  end

  def self.run
    bound(0_i32) { "wrong" }
  end
end

SelectedBlockGenericFixedMismatch.run
CRYSTAL

cat >"$WORK_DIR/reject_receiver_owned_generic_result.cr" <<'CRYSTAL'
class SelectedBlockResultBox(T)
  def initialize(@value : T)
  end

  def each(&block : -> T) : T
    yield
  end
end

class SelectedBlockReceiverOwnedMismatch
  def self.run
    SelectedBlockResultBox(Int32).new(0_i32).each { "wrong" }
  end
end

SelectedBlockReceiverOwnedMismatch.run
CRYSTAL

cat >"$WORK_DIR/reject_named_fixed_by_value.cr" <<'CRYSTAL'
class SelectedBlockNamedFixedMismatch
  def self.bound_named(*, value : T, &block : -> T) : T forall T
    yield
  end

  def self.run
    bound_named(value: 0_i32) { "wrong" }
  end
end

SelectedBlockNamedFixedMismatch.run
CRYSTAL

cat >"$WORK_DIR/reject_wrong_next_result.cr" <<'CRYSTAL'
class SelectedBlockExpectedNext
end

class SelectedBlockWrongNextResult
  def self.needs_expected(&block : -> SelectedBlockExpectedNext) : SelectedBlockExpectedNext
    yield
  end

  def self.run
    needs_expected do
      next 65
      SelectedBlockExpectedNext.new
    end
  end
end

SelectedBlockWrongNextResult.run
CRYSTAL

cat >"$WORK_DIR/reject_nil_fallthrough.cr" <<'CRYSTAL'
class SelectedBlockNilFallthrough
  def self.needs_int(&block : -> Int32) : Int32
    yield
  end

  def self.run(flag : Bool)
    needs_int { if flag; 65; end }
  end
end

SelectedBlockNilFallthrough.run(false)
CRYSTAL

cat >"$WORK_DIR/reject_wrong_class_literal_kind.cr" <<'CRYSTAL'
class SelectedBlockClassValue
end

class SelectedBlockWrongClassLiteralKind
  def self.needs_class(&block : -> SelectedBlockClassValue.class) : SelectedBlockClassValue.class
    yield
  end

  def self.run
    needs_class { SelectedBlockClassValue.new }
  end
end

SelectedBlockWrongClassLiteralKind.run
CRYSTAL

cat >"$WORK_DIR/reject_nested_forwarded_result.cr" <<'CRYSTAL'
class SelectedBlockForwardedResult
  def self.inner(&block : -> String) : String
    yield
  end

  def self.outer(&block : -> Int32) : Int32
    inner { yield }
  end

  def self.run
    outer { 65 }
  end
end

SelectedBlockForwardedResult.run
CRYSTAL

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
  check_native_positive "$stage" positive
}

check_native_positive() {
  local stage="$1" name="$2" status=0
  compile_case "$stage" "$name" || {
    cat "$WORK_DIR/$stage.$name.compile.log" >&2
    echo "FAIL[$stage/$name]: compile failed" >&2
    return 1
  }
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/$stage.$name.bin" 10 512 \
    >"$WORK_DIR/$stage.$name.stdout" 2>"$WORK_DIR/$stage.$name.run.log" || status=$?
  if [[ "$status" != 0 ]]; then
    cat "$WORK_DIR/$stage.$name.run.log" >&2
    echo "FAIL[$stage/$name]: native exit $status" >&2
    return 1
  fi
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$stage.$name.stdout"
}

compile_nocodegen_case() {
  local stage="$1" name="$2" status=0
  local -a command
  if [[ "$stage" == original ]]; then
    command=("$ORIGINAL" 180 8192 build --prelude=empty --no-debug --no-codegen)
  else
    # Adamas --no-codegen currently stops after parsing. Exercise the complete
    # HIR lowering boundary, including selected callback contracts, instead.
    command=("$COMPILER" 180 8192 --no-prelude --no-debug --no-ast-cache --no-llvm-cache --emit hir --no-link)
  fi
  CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$name" ADAMAS_LLVM_CACHE=0 \
    "$SAFE_RUNNER" "${command[@]}" "$WORK_DIR/$name.cr" -o "$WORK_DIR/$stage.$name.check" >"$WORK_DIR/$stage.$name.compile.log" 2>&1 || status=$?
  return "$status"
}

check_nocodegen_acceptance() {
  local stage="$1" name="$2" status=0
  compile_nocodegen_case "$stage" "$name" || status=$?
  if [[ "$status" != 0 || -e "$WORK_DIR/$stage.$name.bin" ]]; then
    cat "$WORK_DIR/$stage.$name.compile.log" >&2
    echo "FAIL[$stage/$name]: expected a successful no-codegen source check" >&2
    return 1
  fi
  if [[ "$stage" == candidate && ! -s "$WORK_DIR/$stage.$name.check.hir" ]]; then
    echo "FAIL[$stage/$name]: source check did not complete HIR lowering" >&2
    return 1
  fi
}

check_nocodegen_rejection() {
  local stage="$1" name="$2" expected="$3" status=0
  compile_nocodegen_case "$stage" "$name" || status=$?
  if [[ "$status" != 1 || -e "$WORK_DIR/$stage.$name.bin" ]]; then
    cat "$WORK_DIR/$stage.$name.compile.log" >&2
    echo "FAIL[$stage/$name]: expected semantic rejection without an executable" >&2
    return 1
  fi
  python3 - "$WORK_DIR/$stage.$name.compile.log" "$expected" <<'PY_TYPE_REJECT'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(errors="replace")
lower = text.lower()
assert "error" in lower, text
assert "syntax error" not in lower and "parser errors" not in lower, text
assert "internal compiler error" not in lower and "unhandled exception" not in lower, text
assert sys.argv[2] in text, text
PY_TYPE_REJECT
}

check_rejection() {
  local stage="$1" name="$2" status=0
  compile_case "$stage" "$name" || status=$?
  if [[ "$status" != 1 || -e "$WORK_DIR/$stage.$name.bin" ]]; then
    cat "$WORK_DIR/$stage.$name.compile.log" >&2
    echo "FAIL[$stage/$name]: expected semantic rejection without an executable" >&2
    return 1
  fi
  python3 - "$WORK_DIR/$stage.$name.compile.log" <<'PY_REJECT'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(errors="replace").lower()
assert "error" in text, text
assert "syntax error" not in text and "parser errors" not in text, text
assert "internal compiler error" not in text and "unhandled exception" not in text, text
PY_REJECT
}

case_enabled() {
  local requested="$1"
  [[ -z "$ONLY_CASES" || ",$ONLY_CASES," == *",$requested,"* ]]
}

stages=(original)
if [[ "$ORIGINAL_ONLY" != 1 ]]; then
  stages+=(candidate)
fi

for stage in "${stages[@]}"; do
  if case_enabled positive; then
    check_positive "$stage"
  fi
  for name in positive_class_output positive_mixed_kind_argument positive_nullable_output positive_yield_discard_result positive_method_nil_result positive_allocator_result positive_default_provenance positive_owner_generic_output; do
    if case_enabled "$name"; then
      check_native_positive "$stage" "$name"
    fi
  done
  if case_enabled positive_array_output_source; then
    check_nocodegen_acceptance "$stage" positive_array_output_source
  fi
  if case_enabled positive_mixed_value_kind_source; then
    check_nocodegen_acceptance "$stage" positive_mixed_value_kind_source
  fi
  if case_enabled reject_mixed_value_kind_source; then
    check_rejection "$stage" reject_mixed_value_kind_source
  fi
  if case_enabled reject_array_output_shape; then
    check_nocodegen_rejection "$stage" reject_array_output_shape "to return Array(T), not String"
  fi
  if case_enabled reject_explicit_defaulted_input; then
    check_nocodegen_rejection "$stage" reject_explicit_defaulted_input "to return Int32, not String"
  fi
  for name in \
    reject_wrong_normal_result \
    reject_anonymous_wrong_result \
    reject_generic_fixed_by_value \
    reject_receiver_owned_generic_result \
    reject_class_receiver_generic_result \
    reject_named_fixed_by_value \
    reject_wrong_next_result \
    reject_nil_fallthrough \
    reject_wrong_class_literal_kind \
    reject_nested_forwarded_result; do
    if case_enabled "$name"; then
      check_rejection "$stage" "$name"
    fi
  done
  if [[ -n "$ONLY_CASES" ]]; then
    echo "PASS[$stage]: $ONLY_CASES"
  else
    echo "PASS[$stage]: typed block outputs, discard contracts, next, escape paths, class literals, and forwarding"
  fi
done
