#!/usr/bin/env bash
# Preserve union element identity and value ownership before opaque MIR allocation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
elif [[ -d "$ROOT_DIR/../crystal/src" ]]; then
  CRYSTAL_STDLIB="$(cd "$ROOT_DIR/../crystal/src" && pwd -P)"
else
  echo "set CRYSTAL_PATH to the external Crystal stdlib source directory" >&2
  exit 2
fi
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -d "$CRYSTAL_STDLIB" ]] || exit 2

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array-union-carrier.XXXXXX")"
cleanup() {
  local status=$?
  for name in empty_struct returned_struct mixed_value nullable_reference; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/empty_struct.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

struct ArrayStartState
  def initialize
  end
end

struct ArrayEndState
  def initialize
  end
end

states = [ArrayStartState.new] of ArrayStartState | ArrayEndState
C.putchar(states[0].is_a?(ArrayStartState) ? 65 : 66)
C.putchar(10)
CRYSTAL
cat >"$WORK_DIR/empty_struct.expected" <<'EXPECTED'
A
EXPECTED
: >"$WORK_DIR/empty_struct.stderr.expected"

cat >"$WORK_DIR/returned_struct.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

struct ArrayValueState
  getter value : Int32
  def initialize(@value : Int32)
  end
end

struct ArrayOtherState
  def initialize
  end
end

def build_states
  [ArrayValueState.new(65)] of ArrayValueState | ArrayOtherState
end

states = build_states
state = states[0]
C.putchar(state.is_a?(ArrayValueState) ? state.value : 66)
C.putchar(10)
CRYSTAL
cat >"$WORK_DIR/returned_struct.expected" <<'EXPECTED'
A
EXPECTED
: >"$WORK_DIR/returned_struct.stderr.expected"

cat >"$WORK_DIR/mixed_value.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

struct MixedArrayPayload
  property value : Int32
  def initialize(@value : Int32)
  end
end

def emit(value : MixedArrayPayload | Int32 | Nil)
  case value
  when MixedArrayPayload
    C.putchar(value.value)
  when Int32
    C.putchar(value)
  when Nil
    C.putchar(67)
  end
end

payload = MixedArrayPayload.new(65)
values = [payload, 66, nil] of MixedArrayPayload | Int32 | Nil
payload.value = 90
emit(values[0])
emit(values[1])
emit(values[2])
C.putchar(10)
CRYSTAL
cat >"$WORK_DIR/mixed_value.expected" <<'EXPECTED'
ABC
EXPECTED
: >"$WORK_DIR/mixed_value.stderr.expected"

cat >"$WORK_DIR/nullable_reference.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

class NullableArrayParent
  getter value : Int32
  def initialize(@value : Int32)
  end
end

class NullableArrayChild < NullableArrayParent
end

values = [NullableArrayChild.new(65), nil] of NullableArrayParent | Nil
first = values[0]
C.putchar(first ? first.value : 66)
C.putchar(values[1].nil? ? 67 : 68)
C.putchar(10)
CRYSTAL
cat >"$WORK_DIR/nullable_reference.expected" <<'EXPECTED'
AC
EXPECTED
: >"$WORK_DIR/nullable_reference.stderr.expected"

compile_run() {
  local name="$1" mode="$2" compiler="$3" status=0
  local source="$WORK_DIR/$name.cr" output="$WORK_DIR/$mode-$name.bin"
  local log="$WORK_DIR/$mode-$name.compile.log" cache="$WORK_DIR/$mode-$name.cache"
  if [[ "$mode" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$source" --no-debug \
      --link-flags=-fuse-ld=/usr/bin/ld -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$source" --no-ast-cache --no-llvm-cache \
      --no-debug --no-prelude -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$mode/$name]: compile exited $status" >&2
    tail -30 "$log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.run.resources" \
    "$SAFE_RUNNER" "$output" 10 512 >"$WORK_DIR/$mode-$name.stdout" \
    2>"$WORK_DIR/$mode-$name.run.log"; then
    echo "FAIL[$mode/$name]: runtime failed" >&2
    cat "$WORK_DIR/$mode-$name.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$mode-$name.run.log"
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$mode-$name.stdout"
  awk '/^=== STDERR ===$/ { capture=1; next } /^\[EXIT: / { capture=0 } capture { print }' \
    "$WORK_DIR/$mode-$name.run.log" >"$WORK_DIR/$mode-$name.stderr"
  diff -u "$WORK_DIR/$name.stderr.expected" "$WORK_DIR/$mode-$name.stderr"
}

# Certify every fixture against the original before testing the candidate.
for name in empty_struct returned_struct mixed_value nullable_reference; do
  compile_run "$name" original "$ORIGINAL_CRYSTAL_BIN"
done
for name in empty_struct returned_struct mixed_value nullable_reference; do
  compile_run "$name" candidate "$COMPILER"
  echo "PASS[$name]: original and candidate stdout and stderr agree"
done
echo "PASS[array-union-carrier]: four original-first fixtures agree"
