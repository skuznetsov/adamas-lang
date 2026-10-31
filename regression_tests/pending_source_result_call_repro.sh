#!/usr/bin/env bash
# A call must expose the selected source body's result before a caller narrows it.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pending-source-result-call.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

cat > "$WORK/direct_nullable_question.cr" <<'CRYSTAL'
@[Link("c")]
lib PendingSourceCallOutput
  fun putchar(value : Int32) : Int32
end

def accept_optional(value : Int32?) : Int32
  PendingSourceCallOutput.putchar(80)
end

struct PendingSourceQuestion
  def maybe_value?(enabled : Bool)
    PendingSourceCallOutput.putchar(65)
    return unless enabled
    67
  end
end

probe = PendingSourceQuestion.new
accept_optional(probe.maybe_value?(true))
accept_optional(probe.maybe_value?(false))
CRYSTAL

cat > "$WORK/direct_nullable_plain.cr" <<'CRYSTAL'
@[Link("c")]
lib PendingSourceCallOutput
  fun putchar(value : Int32) : Int32
end

def accept_optional(value : Int32?) : Int32
  PendingSourceCallOutput.putchar(80)
end

struct PendingSourcePlain
  def maybe_value(enabled : Bool)
    PendingSourceCallOutput.putchar(66)
    return unless enabled
    68
  end
end

probe = PendingSourcePlain.new
accept_optional(probe.maybe_value(true))
accept_optional(probe.maybe_value(false))
CRYSTAL

cat > "$WORK/direct_tuple_question.cr" <<'CRYSTAL'
@[Link("c")]
lib PendingSourceCallOutput
  fun putchar(value : Int32) : Int32
end

def accept_pair(value : Tuple(Int32?, Int32?)) : Int32
  PendingSourceCallOutput.putchar(84)
end

struct PendingSourceTuple
  def maybe_pair?(enabled : Bool)
    PendingSourceCallOutput.putchar(67)
    return {nil, nil} unless enabled
    left = 69
    right = 70
    return left, right
  end
end

probe = PendingSourceTuple.new
accept_pair(probe.maybe_pair?(true))
accept_pair(probe.maybe_pair?(false))
CRYSTAL

cat > "$WORK/zero_control.cr" <<'CRYSTAL'
@[Link("c")]
lib PendingSourceCallOutput
  fun putchar(value : Int32) : Int32
end

def accept_integer(value : Int32) : Int32
  PendingSourceCallOutput.putchar(68)
end

struct PendingSourceZero
  def zero? : Int32
    0
  end
end

accept_integer(PendingSourceZero.new.zero?)
CRYSTAL

cat > "$WORK/bool_control.cr" <<'CRYSTAL'
@[Link("c")]
lib PendingSourceCallOutput
  fun putchar(value : Int32) : Int32
end

def accept_boolean(value : Bool) : Int32
  PendingSourceCallOutput.putchar(69)
end

struct PendingSourceBool
  def ready?(value : Bool)
    value
  end
end

probe = PendingSourceBool.new
accept_boolean(probe.ready?(true))
accept_boolean(probe.ready?(false))
CRYSTAL

cat > "$WORK/undefined_call.cr" <<'CRYSTAL'
struct PendingSourceUndefined
  def run
    missing_query?
  end
end

PendingSourceUndefined.new.run
CRYSTAL

cat > "$WORK/bad_argument.cr" <<'CRYSTAL'
struct PendingSourceBadArgument
  def accepts_integer?(value : Int32)
    value
  end
end

PendingSourceBadArgument.new.accepts_integer?("wrong")
CRYSTAL

cases=(direct_nullable_question direct_nullable_plain direct_tuple_question zero_control bool_control undefined_call bad_argument)
outputs=(APAP BPBP CTCT D EE '' '')

run_case() {
  local mode="$1" index="$2" probe="${cases[$2]}" status
  if [[ "$probe" == undefined_call || "$probe" == bad_argument ]]; then
    set +e
    "${compile[@]}" "$WORK/$probe.cr" -o "$WORK/$mode.$probe" > "$WORK/$mode.$probe.compile.log" 2>&1
    status=$?
    set -e
    if [[ "$status" != 1 ]]; then
      cat "$WORK/$mode.$probe.compile.log" >&2
      printf 'FAIL: %s %s expected compile exit1, got%s\n' "$mode" "$probe" "$status" >&2
      return 1
    fi
    if [[ "$probe" == undefined_call ]]; then
      grep -Eq "undefined (local variable or )?method.*missing_query|undefined function.*missing_query|no overload matches.*missing_query" "$WORK/$mode.$probe.compile.log" || {
        cat "$WORK/$mode.$probe.compile.log" >&2
        return 1
      }
    else
      grep -Eq 'no overload matches|expected argument.*Int32|got String' "$WORK/$mode.$probe.compile.log" || {
        cat "$WORK/$mode.$probe.compile.log" >&2
        return 1
      }
    fi
  else
    "${compile[@]}" "$WORK/$probe.cr" -o "$WORK/$mode.$probe" > "$WORK/$mode.$probe.compile.log" 2>&1 || {
      cat "$WORK/$mode.$probe.compile.log" >&2
      return 1
    }
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/$mode.$probe" 5 512 \
      > "$WORK/$mode.$probe.stdout" 2> "$WORK/$mode.$probe.run.log" || {
      cat "$WORK/$mode.$probe.run.log" >&2
      return 1
    }
    printf '%s' "${outputs[$index]}" > "$WORK/$probe.expected.stdout"
    diff -u "$WORK/$probe.expected.stdout" "$WORK/$mode.$probe.stdout" || return 1
  fi
  printf 'PASS: %s %s\n' "$mode" "$probe"
}

modes=(stock lazy eager)
[[ "${ORIGINAL_ONLY:-0}" == 1 ]] && modes=(stock)
[[ "${CANDIDATE_ONLY:-0}" == 1 ]] && modes=(lazy eager)
failed=0
for mode in "${modes[@]}"; do
  if [[ "$mode" == stock ]]; then
    compile=(env CRYSTAL_CACHE_DIR="$WORK/cache.stock" "$SAFE" "$ORIGINAL" 120 4096 build
      --prelude=empty --single-module --no-debug --link-flags="$LINK_FLAGS")
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" == eager ]] && mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    compile=("${mode_env[@]}" ADAMAS_LLVM_CACHE=0 "$SAFE" "$CANDIDATE" 120 4096
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  for index in "${!cases[@]}"; do
    probe="${cases[$index]}"
    if [[ -n "${ONLY_CASES:-}" && ",${ONLY_CASES}," != *",${probe},"* ]]; then
      continue
    fi
    if ! run_case "$mode" "$index"; then
      printf 'FAIL: %s %s\n' "$mode" "$probe" >&2
      failed=1
      [[ "${CONTINUE_ON_FAILURE:-0}" == 1 ]] || exit 1
    fi
  done
done
exit "$failed"
