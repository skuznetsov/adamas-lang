#!/usr/bin/env bash
# Preserve source restriction identity for applied generic arguments, composite
# types, abstract Int membership, and splat parameters.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-60}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-2048}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/applied-generic-argument-identity.XXXXXX")"

cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 || "${KEEP_ARTIFACTS:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$SAFE_RUNNER" || ! -x "$ADAMAS_BIN" || ! -x "$ORIGINAL_CRYSTAL_BIN" ]]; then
  echo "ERROR: safe runner, candidate compiler, and installed Crystal must be executable" >&2
  exit 2
fi

write_source() {
  local case_name="$1"
  local argument="$2"
  local owner_type='::Path'
  local restriction='T?'
  local parameter='value : T?'
  local method_result='0'
  local source="$WORK_DIR/$case_name.cr"
  if [[ "$case_name" == positive_array_root || "$case_name" == wrong_nested_array ]]; then
    owner_type='Array(::Path)'
  fi
  if [[ "$case_name" == abstract_int_uint64 || "$case_name" == abstract_int_float64 ]]; then
    restriction='T | Int'
    parameter="value : $restriction"
    method_result='value == 0x1_0000_0001_u64 ? 0 : 41'
  fi
  if [[ "$case_name" == numeric_splat_uint64 || "$case_name" == numeric_splat_float64 ]]; then
    parameter='*values : T | Int'
    method_result='values[0] == 0x1_0000_0001_u64 ? 0 : 41'
  fi
  if [[ "$case_name" == plain_numeric_splat_uint64 || "$case_name" == plain_numeric_splat_float64 ]]; then
    parameter='*values : Int'
    method_result='values[0] == 0x1_0000_0001_u64 ? 0 : 41'
  fi
  cat >"$source" <<CRYSTAL
lib AppliedGenericIdentityProbe
  fun exit(status : Int32) : NoReturn
  fun getpid : Int32
end

fun __crystal_raise_overflow : NoReturn
  AppliedGenericIdentityProbe.exit(99)
end

class Path
end

module Crystal
  module System
    class Path
    end

    class Box(T)
      def self.accept($parameter) : Int32
        $method_result
      end
    end
  end
end
CRYSTAL
  if [[ "$case_name" == positive_array_root || "$case_name" == wrong_nested_array ]]; then
    local element_type='::Path'
    if [[ "$case_name" == wrong_nested_array ]]; then
      element_type='Crystal::System::Path'
    fi
    cat >>"$source" <<CRYSTAL
def applied_generic_identity_array : Array($element_type)
  Pointer(Void).new(0_u64).as(Array($element_type))
end
CRYSTAL
    if [[ "$case_name" == positive_array_root ]]; then
      cat >>"$source" <<CRYSTAL
if AppliedGenericIdentityProbe.getpid < 0
  AppliedGenericIdentityProbe.exit(
    Crystal::System::Box($owner_type).accept(applied_generic_identity_array)
  )
end
AppliedGenericIdentityProbe.exit(0)
CRYSTAL
    else
      cat >>"$source" <<CRYSTAL
Crystal::System::Box($owner_type).accept(applied_generic_identity_array)
CRYSTAL
    fi
    return
  fi
  if [[ "$case_name" == wrong_nested_path || "$case_name" == wrong_nested_array ]]; then
    cat >>"$source" <<CRYSTAL
Crystal::System::Box($owner_type).accept($argument)
CRYSTAL
  else
    cat >>"$source" <<CRYSTAL
AppliedGenericIdentityProbe.exit(
  Crystal::System::Box($owner_type).accept($argument)
)
CRYSTAL
  fi
}

write_source positive_array_root ''
write_source wrong_nested_array ''
write_source abstract_int_uint64 '0x1_0000_0001_u64'
write_source abstract_int_float64 '1.0'
write_source numeric_splat_uint64 '0x1_0000_0001_u64'
write_source numeric_splat_float64 '1.0'
write_source plain_numeric_splat_uint64 '0x1_0000_0001_u64'
write_source plain_numeric_splat_float64 '1.0'
write_source positive_root_path '::Path.new'
write_source positive_nil nil
write_source wrong_nested_path 'Crystal::System::Path.new'

compile_case() {
  local stage="$1" compiler="$2" name="$3" mode="$4"
  local source="$WORK_DIR/$name.cr"
  local binary="$WORK_DIR/$stage-$name"
  local log="$WORK_DIR/$stage-$name.log"
  local cache="$WORK_DIR/$stage-$name.cache"
  local rc=0
  mkdir -p "$cache"

  if [[ "$stage" == original ]]; then
    CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUNNER" "$compiler" \
      "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" build --prelude=empty \
      --no-debug "$source" -o "$binary" >"$log" 2>&1 || rc=$?
  else
    CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
      "$SAFE_RUNNER" "$compiler" "$COMPILE_TIMEOUT_SEC" \
      "$COMPILE_MAX_MEM_MB" "$source" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1 || rc=$?
  fi

  if [[ "$mode" == reject ]]; then
    local diagnostic_ok=0
    local rejection_ok=0
    if [[ "$name" == wrong_nested_path || "$name" == wrong_nested_array ]]; then
      if rg -q "expected argument|no overload matches" "$log" && \
        rg -q "Crystal::System::Path" "$log"; then
        diagnostic_ok=1
        rejection_ok=1
      fi
    elif [[ "$name" == abstract_int_float64 || "$name" == numeric_splat_float64 || "$name" == plain_numeric_splat_float64 ]]; then
      if [[ "$stage" == original ]] && { rg -q "can't use Int in unions" "$log" || { rg -q "no overload matches" "$log" && rg -q "Float64" "$log"; }; }; then
        diagnostic_ok=1
        rejection_ok=1
      elif rg -q "expected argument|no overload matches" "$log" && rg -q "Float64" "$log"; then
        diagnostic_ok=1
        rejection_ok=1
      fi
    fi
    if [[ "$rc" != 1 ]] || [[ "$diagnostic_ok" != 1 ]] || [[ "$rejection_ok" != 1 ]]; then
      cat "$log" >&2
      echo "FAIL $stage $name: expected ordinary source restriction rejection (exit 1)" >&2
      return 1
    fi
    printf 'PASS %s %s rejected source-incompatible argument\n' "$stage" "$name"
    return 0
  fi

  if [[ "$rc" != 0 ]]; then
    cat "$log" >&2
    echo "FAIL $stage $name: expected source-compatible argument to compile" >&2
    return 1
  fi

  rc=0
  "$SAFE_RUNNER" "$binary" 5 512 >"$log" 2>&1 || rc=$?
  if [[ "$rc" != 0 ]] || ! rg -Fq '[EXIT: 0]' "$log"; then
    cat "$log" >&2
    echo "FAIL $stage $name: native run did not exit zero" >&2
    return 1
  fi
  if [[ "$name" == positive_array_root ]]; then
    printf 'PASS %s %s type-check and guarded run exit=0 (Array arm is never constructed)\n' "$stage" "$name"
  else
    printf 'PASS %s %s compile-and-run exit=0\n' "$stage" "$name"
  fi
}

# Establish the intended Crystal behavior before checking the candidate.
compile_case original "$ORIGINAL_CRYSTAL_BIN" positive_root_path allow
compile_case original "$ORIGINAL_CRYSTAL_BIN" positive_nil allow
compile_case original "$ORIGINAL_CRYSTAL_BIN" wrong_nested_path reject
compile_case original "$ORIGINAL_CRYSTAL_BIN" positive_array_root allow
compile_case original "$ORIGINAL_CRYSTAL_BIN" wrong_nested_array reject
compile_case original "$ORIGINAL_CRYSTAL_BIN" abstract_int_uint64 allow
compile_case original "$ORIGINAL_CRYSTAL_BIN" abstract_int_float64 reject
compile_case original "$ORIGINAL_CRYSTAL_BIN" numeric_splat_uint64 allow
compile_case original "$ORIGINAL_CRYSTAL_BIN" numeric_splat_float64 reject
compile_case original "$ORIGINAL_CRYSTAL_BIN" plain_numeric_splat_uint64 allow
compile_case original "$ORIGINAL_CRYSTAL_BIN" plain_numeric_splat_float64 reject

candidate_failures=0
compile_case candidate "$ADAMAS_BIN" positive_root_path allow || candidate_failures=1
compile_case candidate "$ADAMAS_BIN" positive_nil allow || candidate_failures=1
compile_case candidate "$ADAMAS_BIN" wrong_nested_path reject || candidate_failures=1
compile_case candidate "$ADAMAS_BIN" positive_array_root allow || candidate_failures=1
compile_case candidate "$ADAMAS_BIN" wrong_nested_array reject || candidate_failures=1
compile_case candidate "$ADAMAS_BIN" abstract_int_uint64 allow || candidate_failures=1
compile_case candidate "$ADAMAS_BIN" abstract_int_float64 reject || candidate_failures=1
compile_case candidate "$ADAMAS_BIN" numeric_splat_uint64 allow || candidate_failures=1
compile_case candidate "$ADAMAS_BIN" numeric_splat_float64 reject || candidate_failures=1
compile_case candidate "$ADAMAS_BIN" plain_numeric_splat_uint64 allow || candidate_failures=1
compile_case candidate "$ADAMAS_BIN" plain_numeric_splat_float64 reject || candidate_failures=1

if [[ "$candidate_failures" != 0 ]]; then
  echo "FAIL: candidate disagreed with installed Crystal on applied argument or numeric-splat restrictions" >&2
  exit 1
fi

printf 'PASS: applied Box(T) checks root and composite identities plus regular and splat Int admission; Array(Path) is a compile-time guarded arm only\n'
