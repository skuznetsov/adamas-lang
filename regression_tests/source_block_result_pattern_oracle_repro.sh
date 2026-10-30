#!/usr/bin/env bash
# Assert installed Crystal's measured source block-result restriction
# behavior, and require candidate acceptance/rejection parity when supplied.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-}}"
ONLY_CASES="${ONLY_CASES:-}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-180}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"

if [[ ! -x "$SAFE_RUNNER" || -z "$ORIGINAL_CRYSTAL_BIN" || ! -x "$ORIGINAL_CRYSTAL_BIN" ]]; then
  echo "SAFE runner or installed Crystal is unavailable" >&2
  exit 2
fi
if [[ -n "$ADAMAS_BIN" && ! -x "$ADAMAS_BIN" ]]; then
  echo "candidate compiler is unavailable: $ADAMAS_BIN" >&2
  exit 2
fi

CASES=(
  array_bound_distributed
  array_bound_whole_union
  array_bound_concrete
  array_bound_concrete_wrong
  array_unbound_inference
  proc_direct_nil_exact
  proc_direct_nil_discards_string
  proc_direct_nil_discards_noreturn
  proc_direct_string_accepts_noreturn
  proc_tuple_nil_exact
  proc_tuple_nil_discards_string
  proc_tuple_nil_discards_noreturn
  proc_tuple_string_accepts_noreturn
  proc_namedtuple_nil_exact
  proc_namedtuple_nil_discards_string
  proc_namedtuple_nil_discards_noreturn
)

if [[ -n "$ONLY_CASES" ]]; then
  IFS=, read -r -a requested_cases <<<"$ONLY_CASES"
  for requested_case in "${requested_cases[@]}"; do
    found=0
    for known_case in "${CASES[@]}"; do
      [[ "$requested_case" == "$known_case" ]] && found=1
    done
    if [[ "$found" != 1 ]]; then
      echo "unknown source block-result pattern case: $requested_case" >&2
      exit 2
    fi
  done
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/source-block-result-pattern.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/array_prefix.cr" <<'CRYSTAL'
class Array(T)
end

class BoundArrayOutput(T)
  def self.accept(&block : -> Array(T))
    yield
  end
end

class UnboundArrayOutput
  def self.accept(&block : -> Array(T)) forall T
    yield
  end
end

def array_int32 : Array(Int32)
  Pointer(Array(Int32)).new(0_u64).as(Array(Int32))
end

def array_string : Array(String)
  Pointer(Array(String)).new(0_u64).as(Array(String))
end

def array_int32_or_string : Array(Int32 | String)
  Pointer(Array(Int32 | String)).new(0_u64).as(Array(Int32 | String))
end
CRYSTAL

write_array_case() {
  local name="$1"
  cp "$WORK_DIR/array_prefix.cr" "$WORK_DIR/$name.cr"
  cat >>"$WORK_DIR/$name.cr"
}

write_array_case array_bound_distributed <<'CRYSTAL'
def check(flag : Bool)
  BoundArrayOutput(Int32 | String).accept do
    if flag
      array_int32
    else
      array_string
    end
  end
end

check(false)
CRYSTAL

write_array_case array_bound_whole_union <<'CRYSTAL'
BoundArrayOutput(Int32 | String).accept { array_int32_or_string }
CRYSTAL

write_array_case array_bound_concrete <<'CRYSTAL'
BoundArrayOutput(Int32).accept { array_int32 }
CRYSTAL

write_array_case array_bound_concrete_wrong <<'CRYSTAL'
BoundArrayOutput(Int32).accept { array_string }
CRYSTAL

write_array_case array_unbound_inference <<'CRYSTAL'
UnboundArrayOutput.accept { array_int32 }
CRYSTAL

cat >"$WORK_DIR/proc_prefix.cr" <<'CRYSTAL'
lib SourceBlockResultOracleC
  fun stop(status : Int32) : NoReturn
end

class ProcBlockResultOutput
  def self.direct_nil(&block : -> Proc(Int32, Nil))
    yield
  end

  def self.direct_string(&block : -> Proc(Int32, String))
    yield
  end

  def self.tuple_nil(&block : -> Tuple(Proc(Int32, Nil)))
    yield
  end

  def self.tuple_string(&block : -> Tuple(Proc(Int32, String)))
    yield
  end

  def self.namedtuple_nil(&block : -> NamedTuple(callback: Proc(Int32, Nil)))
    yield
  end
end
CRYSTAL

write_proc_case() {
  local name="$1"
  cp "$WORK_DIR/proc_prefix.cr" "$WORK_DIR/$name.cr"
  cat >>"$WORK_DIR/$name.cr"
}

write_proc_case proc_direct_nil_exact <<'CRYSTAL'
ProcBlockResultOutput.direct_nil { ->(value : Int32) { nil } }
CRYSTAL

write_proc_case proc_direct_nil_discards_string <<'CRYSTAL'
ProcBlockResultOutput.direct_nil { ->(value : Int32) { "value" } }
CRYSTAL

write_proc_case proc_direct_nil_discards_noreturn <<'CRYSTAL'
ProcBlockResultOutput.direct_nil { ->(value : Int32) { SourceBlockResultOracleC.stop(91) } }
CRYSTAL

write_proc_case proc_direct_string_accepts_noreturn <<'CRYSTAL'
ProcBlockResultOutput.direct_string { ->(value : Int32) { SourceBlockResultOracleC.stop(92) } }
CRYSTAL

write_proc_case proc_tuple_nil_exact <<'CRYSTAL'
ProcBlockResultOutput.tuple_nil { { ->(value : Int32) { nil } } }
CRYSTAL

write_proc_case proc_tuple_nil_discards_string <<'CRYSTAL'
ProcBlockResultOutput.tuple_nil { { ->(value : Int32) { "value" } } }
CRYSTAL

write_proc_case proc_tuple_nil_discards_noreturn <<'CRYSTAL'
ProcBlockResultOutput.tuple_nil { { ->(value : Int32) { SourceBlockResultOracleC.stop(93) } } }
CRYSTAL

write_proc_case proc_tuple_string_accepts_noreturn <<'CRYSTAL'
ProcBlockResultOutput.tuple_string { { ->(value : Int32) { SourceBlockResultOracleC.stop(94) } } }
CRYSTAL

write_proc_case proc_namedtuple_nil_exact <<'CRYSTAL'
ProcBlockResultOutput.namedtuple_nil { {callback: ->(value : Int32) { nil }} }
CRYSTAL

write_proc_case proc_namedtuple_nil_discards_string <<'CRYSTAL'
ProcBlockResultOutput.namedtuple_nil { {callback: ->(value : Int32) { "value" }} }
CRYSTAL

write_proc_case proc_namedtuple_nil_discards_noreturn <<'CRYSTAL'
ProcBlockResultOutput.namedtuple_nil { {callback: ->(value : Int32) { SourceBlockResultOracleC.stop(95) }} }
CRYSTAL

case_enabled() {
  local requested="$1"
  [[ -z "$ONLY_CASES" || ",$ONLY_CASES," == *",$requested,"* ]]
}

compile_case() {
  local stage="$1" name="$2" status=0 expected
  local source="$WORK_DIR/$name.cr"
  local log="$WORK_DIR/$stage.$name.compile.log"
  mkdir -p "$WORK_DIR/cache.$stage.$name"

  if [[ "$stage" == original ]]; then
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$name" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" "$COMPILE_TIMEOUT_SEC" \
      "$COMPILE_MAX_MEM_MB" build --prelude=empty --no-debug --no-codegen \
      "$source" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$name" ADAMAS_LLVM_CACHE=0 \
      "$SAFE_RUNNER" "$ADAMAS_BIN" "$COMPILE_TIMEOUT_SEC" \
      "$COMPILE_MAX_MEM_MB" "$source" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache --emit hir --no-link \
      -o "$WORK_DIR/$name.candidate" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi

  expected="$(expected_original_status "$name")"
  if [[ "$status" != "$expected" ]]; then
    printf 'MISMATCH[%s] %s exit=%s expected=%s' "$stage" "$name" "$status" "$expected"
  else
    printf 'PASS[%s] %s exit=%s' "$stage" "$name" "$status"
  fi
  if [[ "$status" != 0 ]]; then
    local diagnostic
    diagnostic="$(rg -m1 '(^Error:|error:|syntax error|expected block|no overload matches|undefined method)' "$log" || true)"
    if [[ -n "$diagnostic" ]]; then
      printf ' diagnostic=%s' "$diagnostic"
    fi
  fi
  printf '\n'
  if [[ "$status" != "$expected" ]]; then
    return 1
  fi
}

expected_original_status() {
  case "$1" in
    array_bound_distributed|array_bound_whole_union|array_bound_concrete|array_unbound_inference|\
    proc_direct_nil_exact|proc_direct_nil_discards_string|proc_direct_nil_discards_noreturn|\
    proc_direct_string_accepts_noreturn|proc_tuple_nil_exact|proc_tuple_string_accepts_noreturn|\
    proc_namedtuple_nil_exact|proc_namedtuple_nil_discards_string|proc_namedtuple_nil_discards_noreturn)
      printf '0'
      ;;
    array_bound_concrete_wrong|proc_tuple_nil_discards_string|proc_tuple_nil_discards_noreturn)
      printf '1'
      ;;
    *)
      echo "missing installed Crystal expectation for $1" >&2
      return 2
      ;;
  esac
}

for stage in original candidate; do
  if [[ "$stage" == candidate && -z "$ADAMAS_BIN" ]]; then
    break
  fi
  for name in "${CASES[@]}"; do
    if case_enabled "$name"; then
      compile_case "$stage" "$name"
    fi
  done
done

printf 'Source block-result expectations and supplied candidate parity passed.\n'
