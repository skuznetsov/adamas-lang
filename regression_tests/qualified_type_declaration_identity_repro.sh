#!/usr/bin/env bash
# Enum and alias declarations must preserve their complete path and root.
# Namespace separators must not be consumed as enum base-type separators.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
# Oracle-only qualification: ORIGINAL_ONLY=1 CRYSTAL_BIN=path/to/crystal $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
KEEP_ARTIFACTS="${KEEP_ARTIFACTS:-0}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qualified-declarations.XXXXXX")"

cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 || "$KEEP_ARTIFACTS" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ "$ORIGINAL_ONLY" != "0" && "$ORIGINAL_ONLY" != "1" ]]; then
  echo "ERROR: ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" ]]; then
  echo "ERROR: safe runner is unavailable" >&2
  exit 2
fi
if [[ -n "$CRYSTAL_BIN" && ! -x "$CRYSTAL_BIN" ]]; then
  echo "ERROR: original Crystal compiler is not executable: $CRYSTAL_BIN" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" == "1" && -z "$CRYSTAL_BIN" ]]; then
  echo "ERROR: ORIGINAL_ONLY=1 requires CRYSTAL_BIN or ORIGINAL_CRYSTAL_BIN" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" != "1" && ! -x "$ADAMAS_BIN" ]]; then
  echo "ERROR: Adamas compiler is not executable: $ADAMAS_BIN" >&2
  exit 2
fi

cat > "$WORK_DIR/qualified_declarations.cr" <<'CR'
lib LibC
  fun putchar(value : Int32) : Int32
end
module EnumRoot
end
enum EnumRoot::Severity : UInt8
  Active = 65
end
alias EnumRoot::Level = EnumRoot::Severity
alias QualifiedBuiltinPrefix = UInt8
alias QualifiedBuiltinPrefix::QualifiedDeclaredValue = Int32
alias QualifiedNilPrefix = Nil
alias QualifiedNilPrefix::QualifiedDeclaredValue = Int32
alias QualifiedPointerHead = Pointer
alias QualifiedPointerHead::QualifiedDeclaredValue = Int32
class QualifiedGenericOwner(T)
end
alias QualifiedGenericHead = QualifiedGenericOwner
alias QualifiedGenericHead::QualifiedDeclaredValue = Int32

def emit_level(value : EnumRoot::Level)
  LibC.putchar(value.value.to_i32)
end
module EnumScope
  module EnumRoot
  end
  enum EnumRoot::Relative : UInt8
    Active = 66
  end
  enum ::EnumRoot::Absolute : UInt8
    Active = 67
  end
  enum ::BareRootLevel : UInt8
    Active = 68
  end
  # A complete prefix can name this scope itself, without duplicating it.
  enum EnumScope::RepeatedOwner : UInt8
    Active = 72
  end
  alias ::RootQualifiedByte = UInt8
  alias Child::QualifiedByte = UInt8
end
class EnumClassOwner
  enum ::EnumRoot::FromClass : UInt8
    Active = 70
  end
  enum Child::Level : UInt8
    Active = 71
  end
  {% if true %}
    enum ::EnumRoot::FromMacro : UInt8
      Active = 75
    end
  {% end %}
  {% if true %}
    @[Flags]
    enum ::EnumRoot::GeneratedFlags : UInt8
      First
      Second
      Eight = 8
      Next
    end
  {% end %}
end
enum EnumClassOwner::Level : UInt8
  Active = 69
end
enum EnumRoot::DefaultLevel
  First
  Second
end

def emit_root_byte(value : ::RootQualifiedByte)
  LibC.putchar(value.to_i32)
end
def emit_nested_byte(value : EnumScope::Child::QualifiedByte)
  LibC.putchar(value.to_i32)
end
emit_level(EnumRoot::Severity::Active)
LibC.putchar(EnumScope::EnumRoot::Relative::Active.value.to_i32)
LibC.putchar(::EnumRoot::Absolute::Active.value.to_i32)
LibC.putchar(::BareRootLevel::Active.value.to_i32)
LibC.putchar(EnumClassOwner::Level::Active.value.to_i32)
LibC.putchar(::EnumRoot::FromClass::Active.value.to_i32)
LibC.putchar(EnumClassOwner::Child::Level::Active.value.to_i32)
LibC.putchar(EnumScope::RepeatedOwner::Active.value.to_i32)
emit_root_byte(73_u8)
emit_nested_byte(74_u8)
LibC.putchar(EnumRoot::DefaultLevel::Second.value.to_i32 &+ 74)
LibC.putchar(::EnumRoot::FromMacro::Active.value.to_i32)
LibC.putchar(::EnumRoot::GeneratedFlags::First.value.to_i32 &+ 64)
LibC.putchar(::EnumRoot::GeneratedFlags::Second.value.to_i32 &+ 64)
LibC.putchar(::EnumRoot::GeneratedFlags::Eight.value.to_i32 &+ 64)
LibC.putchar(::EnumRoot::GeneratedFlags::Next.value.to_i32 &+ 64)
LibC.putchar(81.as(UInt8::QualifiedDeclaredValue))

# Nominal aliases must be published before a subsequent enum declaration.
alias QualifiedNominalEnumPrefix = Int32
enum QualifiedNominalEnumPrefix::OrderedLevel : UInt8
  Active = 82
end
LibC.putchar(Int32::OrderedLevel::Active.value.to_i32)
# A namespace created by a declaration can be reopened by a real module.
enum QualifiedImplicitModule::Nested::First : UInt8
  Active = 83
end
module QualifiedImplicitModule::Nested
  enum Second : UInt8
    Active = 84
  end
end
LibC.putchar(QualifiedImplicitModule::Nested::First::Active.value.to_i32)
LibC.putchar(QualifiedImplicitModule::Nested::Second::Active.value.to_i32)
# Resolving enum constants must still precede a following type-level use.
lib LibC
  QUALIFIED_DECLARATION_ENUM_VALUE = 85
end
enum QualifiedConstantLevel : UInt8
  Active = LibC::QUALIFIED_DECLARATION_ENUM_VALUE
end
class QualifiedEnumConstantConsumer
  VALUE = QualifiedConstantLevel::Active.value
  def self.emit
    LibC.putchar(VALUE.to_i32)
  end
end
QualifiedEnumConstantConsumer.emit
module QualifiedAliasTarget
end
module QualifiedOrderedModule
  alias Prefix = QualifiedAliasTarget
  enum Prefix::ModuleLevel : UInt8
    Active = 86
  end
  module Inner
    alias Prefix = QualifiedAliasTarget
    enum Prefix::NestedLevel : UInt8
      Active = 87
    end
  end
  class Child
    alias Prefix = QualifiedAliasTarget
    enum Prefix::ClassLevel : UInt8
      Active = 88
    end
  end
end
class QualifiedOrderedClass
  alias Prefix = QualifiedAliasTarget
  enum Prefix::RootClassLevel : UInt8
    Active = 89
  end
end
LibC.putchar(QualifiedAliasTarget::ModuleLevel::Active.value.to_i32)
LibC.putchar(QualifiedAliasTarget::NestedLevel::Active.value.to_i32)
LibC.putchar(QualifiedAliasTarget::ClassLevel::Active.value.to_i32)
LibC.putchar(QualifiedAliasTarget::RootClassLevel::Active.value.to_i32)
# Regex is predefined by the original compiler before its source reopening.
enum Regex::QualifiedLevel : UInt8
  Active = 90
end
class Regex
end
LibC.putchar(Regex::QualifiedLevel::Active.value.to_i32)
class EnumClassOwner::QualifiedChild
end
module EnumClassOwner::QualifiedMembers
end
module QualifiedActualModule
end
alias QualifiedModuleAlias = QualifiedActualModule
module QualifiedModuleAlias
  enum Level : UInt8
    Active = 97
  end
end
LibC.putchar(QualifiedActualModule::Level::Active.value.to_i32)
LibC.putchar(10)
CR

cat > "$WORK_DIR/missing_root_enum.cr" <<'CR'
module EnumScope
  enum OnlyLocalLevel
    Active
    def self.marker
      1
    end
  end
  def self.run
    ::OnlyLocalLevel.marker
  end
end
EnumScope.run
CR

cat > "$WORK_DIR/wrong_nominal_enum.cr" <<'CR'
module EnumRoot
end
enum EnumRoot::Level
  Active
end
module OtherEnumRoot
end
enum OtherEnumRoot::Level
  Active
end
def accept_level(value : EnumRoot::Level)
  value
end
accept_level(OtherEnumRoot::Level::Active)
CR
cat > "$WORK_DIR/enum_namespace.cr" <<'CR'
enum InvalidEnumPrefix
  Original
end
alias InvalidEnumPrefix::Nested = Int32
CR
cat > "$WORK_DIR/constant_namespace.cr" <<'CR'
InvalidConstantPrefix = 1
enum InvalidConstantPrefix::Nested
  Original
end
CR
cat > "$WORK_DIR/alias_enum_namespace.cr" <<'CR'
enum InvalidEnumTarget
  Original
end
alias InvalidAliasPrefix = InvalidEnumTarget
alias InvalidAliasPrefix::Nested = Int32
CR
cat > "$WORK_DIR/alias_union_namespace.cr" <<'CR'
alias InvalidUnionPrefix = Int32 | String
alias InvalidUnionPrefix::Nested = Int32
CR
cat > "$WORK_DIR/alias_proc_namespace.cr" <<'CR'
alias InvalidProcPrefix = Proc(Int32)
alias InvalidProcPrefix::Nested = Int32
CR
cat > "$WORK_DIR/alias_tuple_namespace.cr" <<'CR'
alias InvalidTuplePrefix = Tuple(Int32)
alias InvalidTuplePrefix::Nested = Int32
CR
cat > "$WORK_DIR/alias_pointer_namespace.cr" <<'CR'
alias InvalidPointerPrefix = Pointer(Int32)
alias InvalidPointerPrefix::Nested = Int32
CR
cat > "$WORK_DIR/alias_static_array_namespace.cr" <<'CR'
alias InvalidArrayPrefix = StaticArray(Int32, 1)
alias InvalidArrayPrefix::Nested = Int32
CR
cat > "$WORK_DIR/alias_generic_instance_namespace.cr" <<'CR'
class InvalidGenericNamespace(T)
end
alias InvalidGenericInstancePrefix = InvalidGenericNamespace(Int32)
alias InvalidGenericInstancePrefix::Nested = Int32
CR
cat > "$WORK_DIR/alias_void_namespace.cr" <<'CR'
alias InvalidVoidPrefix = Void
alias InvalidVoidPrefix::Nested = Int32
CR
cat > "$WORK_DIR/alias_noreturn_namespace.cr" <<'CR'
alias InvalidNoReturnPrefix = NoReturn
alias InvalidNoReturnPrefix::Nested = Int32
CR
cat > "$WORK_DIR/nested_enum_prefix_first.cr" <<'CR'
module InvalidNestedOwner
  enum Kind
    Active
  end
end
enum InvalidNestedOwner::Kind::Nested
  Active
end
CR
cat > "$WORK_DIR/nested_enum_prefix_later.cr" <<'CR'
enum InvalidNestedOwner::Kind::Nested
  Active
end
module InvalidNestedOwner
  enum Kind
    Active
  end
end
CR
cat > "$WORK_DIR/nested_union_prefix_first.cr" <<'CR'
module InvalidNestedOwner
  alias Kind = Int32 | String
end
enum InvalidNestedOwner::Kind::Nested
  Active
end
CR
cat > "$WORK_DIR/nested_union_prefix_later.cr" <<'CR'
enum InvalidNestedOwner::Kind::Nested
  Active
end
module InvalidNestedOwner
  alias Kind = Int32 | String
end
CR
cat > "$WORK_DIR/implicit_module_class_collision.cr" <<'CR'
enum QualifiedImplicitClass::Level
  Active
end
class QualifiedImplicitClass
end
CR
cat > "$WORK_DIR/implicit_module_struct_collision.cr" <<'CR'
enum QualifiedImplicitStruct::Level
  Active
end
struct QualifiedImplicitStruct
end
CR
cat > "$WORK_DIR/implicit_module_alias_collision.cr" <<'CR'
enum QualifiedImplicitAlias::Level
  Active
end
alias QualifiedImplicitAlias = Int32
CR
cat > "$WORK_DIR/implicit_module_enum_collision.cr" <<'CR'
enum QualifiedImplicitEnum::Level
  Active
end
enum QualifiedImplicitEnum
  Active
end
CR
cat > "$WORK_DIR/nested_module_enum_before_alias.cr" <<'CR'
module QualifiedAliasTarget
end
module Outer
  module Inner
    enum Prefix::Level
      Active
    end
    alias Prefix = QualifiedAliasTarget
  end
end
CR
cat > "$WORK_DIR/module_enum_before_alias.cr" <<'CR'
module QualifiedAliasTarget
end
module Outer
  enum Prefix::Level
    Active
  end
  alias Prefix = QualifiedAliasTarget
end
CR
cat > "$WORK_DIR/nested_class_enum_before_alias.cr" <<'CR'
module QualifiedAliasTarget
end
module Outer
  class Inner
    enum Prefix::Level
      Active
    end
    alias Prefix = QualifiedAliasTarget
  end
end
CR
cat > "$WORK_DIR/class_enum_before_alias.cr" <<'CR'
module QualifiedAliasTarget
end
class Outer
  enum Prefix::Level
    Active
  end
  alias Prefix = QualifiedAliasTarget
end
CR
cat > "$WORK_DIR/backend_set_namespace_collision.cr" <<'CR'
enum Set::QualifiedLevel
  Active
end
class Set(T)
end
CR
cat > "$WORK_DIR/backend_iterator_namespace_collision.cr" <<'CR'
enum Iterator::QualifiedLevel
  Active
end
class Iterator(T)
end
CR
cat > "$WORK_DIR/reopened_module_enum_collision.cr" <<'CR'
enum QualifiedReopenedEnum::Level
  Active
end
module QualifiedReopenedEnum
end
enum QualifiedReopenedEnum
  Active
end
CR
cat > "$WORK_DIR/reopened_module_alias_collision.cr" <<'CR'
enum QualifiedReopenedAlias::Level
  Active
end
module QualifiedReopenedAlias
end
alias QualifiedReopenedAlias = Int32
CR
cat > "$WORK_DIR/enum_before_module_collision.cr" <<'CR'
enum QualifiedFutureModule
  Active
end
module QualifiedFutureModule
end
CR
cat > "$WORK_DIR/module_before_class_collision.cr" <<'CR'
module QualifiedFutureClass
end
class QualifiedFutureClass
end
CR
cat > "$WORK_DIR/class_before_module_collision.cr" <<'CR'
class QualifiedDeclaredClass
end
module QualifiedDeclaredClass
end
CR
cat > "$WORK_DIR/predefined_class_module_collision.cr" <<'CR'
module Regex
end
CR
cat > "$WORK_DIR/alias_union_module_collision.cr" <<'CR'
alias QualifiedNonModuleAlias = Int32 | String
module QualifiedNonModuleAlias
end
CR
cat > "$WORK_DIR/alias_class_module_collision.cr" <<'CR'
class QualifiedAliasClass
end
alias QualifiedNonModuleAlias = QualifiedAliasClass
module QualifiedNonModuleAlias
end
CR
cat > "$WORK_DIR/alias_void_module_collision.cr" <<'CR'
alias QualifiedNonModuleAlias = Void
module QualifiedNonModuleAlias
end
CR
POSITIVE=qualified_declarations
NEGATIVES=(missing_root_enum wrong_nominal_enum enum_namespace constant_namespace alias_enum_namespace alias_union_namespace alias_proc_namespace alias_tuple_namespace alias_pointer_namespace alias_static_array_namespace alias_generic_instance_namespace alias_void_namespace alias_noreturn_namespace nested_enum_prefix_first nested_enum_prefix_later nested_union_prefix_first nested_union_prefix_later implicit_module_class_collision implicit_module_struct_collision implicit_module_alias_collision implicit_module_enum_collision nested_module_enum_before_alias module_enum_before_alias nested_class_enum_before_alias class_enum_before_alias backend_set_namespace_collision backend_iterator_namespace_collision reopened_module_enum_collision reopened_module_alias_collision enum_before_module_collision module_before_class_collision class_before_module_collision predefined_class_module_collision alias_union_module_collision alias_class_module_collision alias_void_module_collision)
EXPECTED_OUTPUT='ABCDEFGHIJKKABHPQRSTUVWXYZa'

exit_code_of() {
  (grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9') || true
}

# Semantic negative cases must be ordinary compiler diagnostics. A timeout,
# resource kill, crash, or signal is not evidence that the source is rejected.
semantic_rejection() {
  local status="$1" log="$2"
  [[ "$status" == "1" ]] || return 1
  [[ "$(exit_code_of "$log")" == "1" ]] || return 1
  if grep -Eqi '\[(KILL|CRASH)\]|Segfault|Abort|out of memory|resource limit' "$log"; then
    return 1
  fi
  grep -Eqi 'undefined constant|unknown constant|undefined method|not a constant|can.t resolve|no overload|type mismatch|expected .* to be|can.t declare type inside|can.t be used as a namespace|is not a (enum|class|struct|module)|already.*defined' "$log"
}

run_binary_exact() {
  local name="$1" binary="$2" stdout="$3" log="$4" status=0
  if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 256 \
      >"$stdout" 2>"$log"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" != "0" || "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s: safe native run did not exit 0\n' "$name" >&2
    return 1
  fi
  if ! printf '%s\n' "$EXPECTED_OUTPUT" | cmp -s - "$stdout"; then
    printf 'FAIL %s: stdout differed from exact expected output\n' "$name" >&2
    return 1
  fi
}

# Qualify every fixture with original Crystal before running the candidate.
if [[ -n "$CRYSTAL_BIN" ]]; then
  original_log="$WORK_DIR/$POSITIVE.orig.build.log"
  if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$SAFE_RUNNER" "$CRYSTAL_BIN" 120 4096 \
      build --prelude=empty "$WORK_DIR/$POSITIVE.cr" -o "$WORK_DIR/$POSITIVE.orig" \
      >"$original_log" 2>&1; then
    original_build_status=0
  else
    original_build_status=$?
  fi
  if [[ "$original_build_status" != "0" || "$(exit_code_of "$original_log")" != "0" ]]; then
    printf 'ORACLE FAIL: original rejects %s\n' "$POSITIVE" >&2
    cat "$original_log" >&2
    exit 2
  fi
  if ! run_binary_exact "$POSITIVE original" "$WORK_DIR/$POSITIVE.orig" \
      "$WORK_DIR/$POSITIVE.orig.stdout" "$WORK_DIR/$POSITIVE.orig.run.log"; then
    exit 2
  fi

  for name in "${NEGATIVES[@]}"; do
    log="$WORK_DIR/$name.orig.build.log"
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$SAFE_RUNNER" "$CRYSTAL_BIN" 120 4096 \
        build --prelude=empty "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" \
        >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
    if ! semantic_rejection "$status" "$log"; then
      printf 'ORACLE FAIL: expected an ordinary semantic rejection for %s\n' "$name" >&2
      cat "$log" >&2
      exit 2
    fi
  done
fi

if [[ "$ORIGINAL_ONLY" == "1" ]]; then
  printf 'PASS: original Crystal qualified enum and alias declaration identities and strict negatives\n'
  exit 0
fi

failures=0
for mode in lazy eager; do
  if [[ "$mode" == eager ]]; then
    export ADAMAS_EAGER_HIR=1
  else
    unset ADAMAS_EAGER_HIR
  fi
  log="$WORK_DIR/$POSITIVE.$mode.adamas.log"
  if "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$POSITIVE.cr" \
      -o "$WORK_DIR/$POSITIVE.$mode.adamas" >"$log" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" != 0 || "$(exit_code_of "$log")" != 0 ]]; then
    printf 'FAIL %s/%s (compile): %s\n' "$mode" "$POSITIVE" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
  elif run_binary_exact "$POSITIVE $mode candidate" "$WORK_DIR/$POSITIVE.$mode.adamas" \
      "$WORK_DIR/$POSITIVE.$mode.adamas.stdout" "$WORK_DIR/$POSITIVE.$mode.adamas.run.log"; then
    printf 'PASS %s/%s\n' "$mode" "$POSITIVE"
  else
    failures=$((failures + 1))
  fi

  for name in "${NEGATIVES[@]}"; do
    log="$WORK_DIR/$name.$mode.adamas.log"
    if "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
        -o "$WORK_DIR/$name.$mode.adamas" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
    if semantic_rejection "$status" "$log"; then
      printf 'PASS %s/%s (semantic rejection)\n' "$mode" "$name"
    else
      printf 'FAIL %s/%s (not a semantic rejection)\n' "$mode" "$name"
      cat "$log" >&2
      failures=$((failures + 1))
    fi
  done
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d qualified type declaration case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'qualified type declaration cases passed\n'
