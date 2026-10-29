#!/usr/bin/env bash
# Regression for spurious Nil inference from a return-only `while true` loop.
# The conditional assignment case models FdLock's `m, success = ...; m =
# unlock_slow(m) unless success; handle_last_ref(m)` path, where `m` must stay
# UInt32 before primitive bitwise operations.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
CRYSTAL_LIB="${CRYSTAL_LIBRARY_PATH:-/opt/homebrew/lib}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nullable-primitive-receiver.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ ! -x "$SAFE_RUNNER" || ! -x "$ORIGINAL_CRYSTAL" || ! -x "$CANDIDATE" ]]; then
  echo "ERROR: safe runner, original Crystal, and candidate compiler must be executable" >&2
  exit 2
fi

write_cases() {
  cat >"$WORK_DIR/loop_return_u32_type.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_return(m : UInt32, take_first : Bool)
  while true
    if take_first
      return m
    end
    return m
  end
end

def need_u32(value : UInt32) : UInt32
  value
end

LibC.exit(need_u32(loop_return(10_u32, true)) == 10_u32 ? 0 : 1)
CRYSTAL

  cat >"$WORK_DIR/loop_return_i32_type.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_return(m : Int32, take_first : Bool)
  while true
    if take_first
      return m
    end
    return m
  end
end

def need_i32(value : Int32) : Int32
  value
end

LibC.exit(need_i32(loop_return(10, true)) == 10 ? 0 : 1)
CRYSTAL

  cat >"$WORK_DIR/loop_return_operator_receiver.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_return(m : UInt32, take_first : Bool)
  while true
    if take_first
      return m
    end
    return m
  end
end

def probe(success : Bool)
  m, success = {10_u32, success}
  m = loop_return(m, false) unless success
  m & 2_u32
end

LibC.exit(probe(true) == 2_u32 && probe(false) == 2_u32 ? 0 : 1)
CRYSTAL

  cat >"$WORK_DIR/guarded_nullable_u32_control.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

value : UInt32? = 10_u32
if value
  LibC.exit((value & 2_u32) == 2_u32 ? 0 : 1)
else
  LibC.exit(2)
end
CRYSTAL

  cat >"$WORK_DIR/direct_u32_control.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

value : UInt32 = 10_u32
LibC.exit((value & 2_u32) == 2_u32 ? 0 : 1)
CRYSTAL

  cat >"$WORK_DIR/nil_only_control.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

value : UInt32? = nil
if value
  LibC.exit(1)
else
  LibC.exit(0)
end
CRYSTAL

  cat >"$WORK_DIR/while_true_break_i32.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_value
  while true
    break 42
  end
end

def need_i32(value : Int32) : Int32
  value
end

LibC.exit(need_i32(loop_value) == 42 ? 0 : 1)
CRYSTAL

  cat >"$WORK_DIR/while_grouped_true_break_i32.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_value
  while (true)
    break 42
  end
end

def need_i32(value : Int32) : Int32
  value
end

LibC.exit(need_i32(loop_value) == 42 ? 0 : 1)
CRYSTAL

  cat >"$WORK_DIR/while_no_break_nil.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_value(condition : Bool)
  while condition
  end
end

def need_nil(value : Nil) : Nil
  value
end

need_nil(loop_value(false))
LibC.exit(0)
CRYSTAL

  cat >"$WORK_DIR/while_false_break_i32.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_value
  while false
    break 42
  end
end

def need_i32(value : Int32) : Int32
  value
end

LibC.exit(need_i32(loop_value) == 42 ? 0 : 1)
CRYSTAL

  cat >"$WORK_DIR/while_double_not_true_break_i32.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_value
  while !!true
    break 42
  end
end

def need_i32(value : Int32) : Int32
  value
end

LibC.exit(need_i32(loop_value) == 42 ? 0 : 1)
CRYSTAL

  cat >"$WORK_DIR/while_true_mixed_break_nullable.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_value(take_value : Bool)
  while true
    if take_value
      break 42
    else
      break
    end
  end
end

def need_i32(value : Int32) : Int32
  value
end

LibC.exit(need_i32(loop_value(true)) == 42 ? 0 : 1)
CRYSTAL

  cat >"$WORK_DIR/until_false_return_i32.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_return(value : Int32)
  until false
    return value
  end
end

def need_i32(value : Int32) : Int32
  value
end

LibC.exit(need_i32(loop_return(42)) == 42 ? 0 : 1)
CRYSTAL

  cat >"$WORK_DIR/until_false_break_i32.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_value
  until false
    break 42
  end
end

def need_i32(value : Int32) : Int32
  value
end

LibC.exit(need_i32(loop_value) == 42 ? 0 : 1)
CRYSTAL

  cat >"$WORK_DIR/reachable_normal_exit_nil.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop_value(condition : Bool)
  while condition
    break 42
  end
end

def need_i32(value : Int32) : Int32
  value
end

LibC.exit(need_i32(loop_value(false)) == 42 ? 0 : 1)
CRYSTAL
}

write_cases

compile_and_run() {
  local stage="$1" compiler="$2" case_name="$3" source="$4"
  local binary="$WORK_DIR/$stage-$case_name"
  local log="$WORK_DIR/$stage-$case_name.log"
  local cache="$WORK_DIR/$stage-$case_name.cache"
  local status=0
  mkdir -p "$cache"

  if [[ "$stage" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_LIBRARY_PATH="$CRYSTAL_LIB" \
      CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$compiler" 120 4096 build --prelude=empty --no-debug \
      "$source" -o "$binary" >"$log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_LIBRARY_PATH="$CRYSTAL_LIB" \
      CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$compiler" 120 4096 "$source" --no-prelude \
      --no-debug --no-ast-cache --no-llvm-cache -o "$binary" \
      >"$log" 2>&1 || status=$?
  fi

  if [[ $status -ne 0 ]]; then
    printf '%s FAIL %s compile_status=%s' "$stage" "$case_name" "$status"
    local diagnostic
    diagnostic="$(rg -m1 '^error:' "$log" || true)"
    [[ -z "$diagnostic" ]] || printf ' %s' "$diagnostic"
    printf '\n'
    return 1
  fi

  status=0
  "$SAFE_RUNNER" "$binary" 5 512 >"$log" 2>&1 || status=$?
  if [[ $status -ne 0 ]]; then
    printf '%s FAIL %s run_status=%s\n' "$stage" "$case_name" "$status"
    return 1
  fi

  printf '%s PASS %s compile_and_run_exit=0\n' "$stage" "$case_name"
}

compile_expect_nullable_rejection() {
  local stage="$1" compiler="$2" case_name="$3" source="$4"
  local binary="$WORK_DIR/$stage-$case_name"
  local log="$WORK_DIR/$stage-$case_name.log"
  local cache="$WORK_DIR/$stage-$case_name.cache"
  local status=0 diagnostic
  mkdir -p "$cache"

  if [[ "$stage" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_LIBRARY_PATH="$CRYSTAL_LIB" \
      CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$compiler" 120 4096 build --prelude=empty --no-debug \
      "$source" -o "$binary" >"$log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_LIBRARY_PATH="$CRYSTAL_LIB" \
      CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$compiler" 120 4096 "$source" --no-prelude \
      --no-debug --no-ast-cache --no-llvm-cache -o "$binary" \
      >"$log" 2>&1 || status=$?
  fi

  if [[ $status -eq 0 ]]; then
    printf '%s FAIL %s unexpectedly accepted nullable result\n' "$stage" "$case_name"
    return 1
  fi

  diagnostic="$(rg -m1 'Int32.*Nil|Nil.*Int32' "$log" || true)"
  if [[ -z "$diagnostic" ]]; then
    printf '%s FAIL %s rejected for an unrelated reason\n' "$stage" "$case_name"
    return 1
  fi

  printf '%s PASS %s strict_consumer_rejected_nullable_result\n' "$stage" "$case_name"
}

positive_cases=(
  loop_return_u32_type
  loop_return_i32_type
  loop_return_operator_receiver
  guarded_nullable_u32_control
  direct_u32_control
  nil_only_control
  while_true_break_i32
  while_grouped_true_break_i32
  while_no_break_nil
)

nullable_rejection_cases=(
  while_false_break_i32
  while_double_not_true_break_i32
  while_true_mixed_break_nullable
  until_false_return_i32
  until_false_break_i32
  reachable_normal_exit_nil
)

# Qualify every positive and expected rejection against original Crystal
# before compiling the candidate. Original Crystal treats `until false` as
# nullable at a strict Int32 consumer, while `while true` keeps an Int32 break
# value non-nullable.
for case_name in "${positive_cases[@]}"; do
  compile_and_run original "$ORIGINAL_CRYSTAL" "$case_name" "$WORK_DIR/$case_name.cr" || {
    echo "ORACLE FAIL: original Crystal did not qualify $case_name" >&2
    exit 1
  }
done
for case_name in "${nullable_rejection_cases[@]}"; do
  compile_expect_nullable_rejection original "$ORIGINAL_CRYSTAL" "$case_name" \
    "$WORK_DIR/$case_name.cr" || {
    echo "ORACLE FAIL: original Crystal did not reject nullable $case_name as expected" >&2
    exit 1
  }
done

candidate_failures=0
for case_name in "${positive_cases[@]}"; do
  if ! compile_and_run candidate "$CANDIDATE" "$case_name" "$WORK_DIR/$case_name.cr"; then
    candidate_failures=$((candidate_failures + 1))
  fi
done
for case_name in "${nullable_rejection_cases[@]}"; do
  if ! compile_expect_nullable_rejection candidate "$CANDIDATE" "$case_name" \
    "$WORK_DIR/$case_name.cr"; then
    candidate_failures=$((candidate_failures + 1))
  fi
done

if [[ $candidate_failures -ne 0 ]]; then
  printf 'FAIL: candidate differs from original in %s case(s)\n' "$candidate_failures" >&2
  exit 1
fi

echo "nullable_primitive_receiver_repro_ok"
