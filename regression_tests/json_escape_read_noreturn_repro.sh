#!/usr/bin/env bash
# Compare JSON::Builder::Escape#read, typed IO::Memory#read, and an ordinary
# virtual Int32/NoReturn return join against original Crystal.
#
# Usage:
#   CRYSTAL_PATH=/path/to/crystal/src \
#     regression_tests/json_escape_read_noreturn_repro.sh \
#       /path/to/original/crystal /path/to/parent/adamas /path/to/fixed/adamas
#
# ORIGINAL_LINK_FLAGS and ADAMAS_EXTRA_LINK_FLAGS can override the macOS
# default linker flag for other toolchains.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"

if [[ $# -ne 3 ]]; then
  echo "Usage: CRYSTAL_PATH=/path/to/crystal/src $0 <original-crystal> <parent-adamas> <fixed-adamas>" >&2
  exit 2
fi

ORIGINAL_CRYSTAL="$1"
PARENT_COMPILER="$2"
FIXED_COMPILER="$3"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-}"
if [[ -z "$CRYSTAL_STDLIB" || ! -d "$CRYSTAL_STDLIB" ]]; then
  echo "CRYSTAL_PATH must name the original Crystal stdlib source directory" >&2
  exit 2
fi
for executable in "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" "$PARENT_COMPILER" "$FIXED_COMPILER"; do
  if [[ ! -x "$executable" ]]; then
    echo "required executable is unavailable: $executable" >&2
    exit 2
  fi
done

DEFAULT_LINK_FLAGS=""
if [[ "$(uname -s)" == Darwin ]]; then
  DEFAULT_LINK_FLAGS="-fuse-ld=/usr/bin/ld"
fi
ORIGINAL_LINK_FLAGS="${ORIGINAL_LINK_FLAGS-$DEFAULT_LINK_FLAGS}"
ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS-$DEFAULT_LINK_FLAGS}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/json-escape-read-noreturn.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/json_escape_read.cr" <<'CRYSTAL'
require "json"

lib LibC
  fun putchar(c : Int32) : Int32
end

memory = IO::Memory.new
builder = JSON::Builder.new(memory)
builder.document do
  builder.string do |escape_io|
    begin
      escape_io.read(Bytes.new(1))
      LibC.putchar(88) # unexpected return
    rescue
      LibC.putchar(65) # JSON::Builder::Escape#read raises
    end
  end
end
LibC.putchar(10)
CRYSTAL
printf 'A\n' >"$WORK_DIR/json_escape_read.expected"

cat >"$WORK_DIR/typed_io_memory_read.cr" <<'CRYSTAL'
require "json"

lib LibC
  fun putchar(c : Int32) : Int32
end

def check_io_read(io : IO)
  bytes = Bytes.new(3)
  count = io.read(bytes)
  LibC.putchar(count == 3 ? 65 : 88)
  LibC.putchar(bytes[0] == 97_u8 ? 66 : 88)
  LibC.putchar(10)
end

memory = IO::Memory.new("abc")
check_io_read(memory)
CRYSTAL
printf 'AB\n' >"$WORK_DIR/typed_io_memory_read.expected"

cat >"$WORK_DIR/virtual_noreturn_guard.cr" <<'CRYSTAL'
lib LibC
  fun putchar(c : Int32) : Int32
end

abstract class ProbeReader
  abstract def read_token
end

class IntProbeReader < ProbeReader
  def read_token : Int32
    41
  end
end

class BottomProbeReader < ProbeReader
  def read_token : NoReturn
    raise "bottom"
  end
end

def read_token_from(reader : ProbeReader)
  reader.read_token
end

def expect_int(value : Int32)
  LibC.putchar(65)
end

expect_int(read_token_from(IntProbeReader.new))
begin
  read_token_from(BottomProbeReader.new)
rescue
  LibC.putchar(66)
end
LibC.putchar(10)
CRYSTAL
printf 'AB\n' >"$WORK_DIR/virtual_noreturn_guard.expected"

link_args=()
if [[ -n "$ORIGINAL_LINK_FLAGS" ]]; then
  link_args+=("--link-flags=$ORIGINAL_LINK_FLAGS")
fi
adamas_link_args=()
if [[ -n "$ADAMAS_EXTRA_LINK_FLAGS" ]]; then
  adamas_link_args+=("ADAMAS_EXTRA_LINK_FLAGS=$ADAMAS_EXTRA_LINK_FLAGS")
fi

compile_and_run() {
  local mode="$1" compiler="$2" name="$3"
  local source="$WORK_DIR/$name.cr" bin="$WORK_DIR/$mode-$name.bin"
  local compile_log="$WORK_DIR/$mode-$name.compile.log"
  local run_log="$WORK_DIR/$mode-$name.run.log"
  local output="$WORK_DIR/$mode-$name.stdout"
  local status=0

  if [[ "$mode" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/$mode-$name.cache" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$source" --no-debug \
      "${link_args[@]}" -o "$bin" >"$compile_log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/$mode-$name.cache" \
      ADAMAS_LLVM_CACHE=0 "${adamas_link_args[@]}" \
      "$SAFE_RUNNER" "$compiler" 240 8192 "$source" --no-ast-cache \
      --no-llvm-cache --no-debug -o "$bin" >"$compile_log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$mode/$name]: compile exited $status" >&2
    tail -30 "$compile_log" >&2
    return 1
  fi

  if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$bin" 15 1024 \
    >"$output" 2>"$run_log"; then
    if ! grep -Fq '[EXIT: 0]' "$run_log"; then
      echo "FAIL[$mode/$name]: safe runner did not report exit 0" >&2
      cat "$run_log" >&2
      return 1
    fi
  else
    status=$?
    echo "FAIL[$mode/$name]: runtime exited $status" >&2
    cat "$run_log" >&2
    return 1
  fi
}

assert_matches_original() {
  local mode="$1" name="$2"
  if ! cmp -s "$WORK_DIR/original-$name.stdout" "$WORK_DIR/$mode-$name.stdout"; then
    echo "FAIL[$mode/$name]: stdout bytes differ from original Crystal" >&2
    printf 'original:' >&2
    od -An -tx1 "$WORK_DIR/original-$name.stdout" >&2
    printf 'actual:  ' >&2
    od -An -tx1 "$WORK_DIR/$mode-$name.stdout" >&2
    return 1
  fi
}

cases=(json_escape_read typed_io_memory_read virtual_noreturn_guard)

# Establish the original compiler as the first oracle and check its exact bytes
# against each fixture's declared behavior.
for name in "${cases[@]}"; do
  compile_and_run original "$ORIGINAL_CRYSTAL" "$name"
  if ! cmp -s "$WORK_DIR/$name.expected" "$WORK_DIR/original-$name.stdout"; then
    echo "FAIL[original/$name]: stdout bytes differ from the fixture expectation" >&2
    printf 'expected:' >&2
    od -An -tx1 "$WORK_DIR/$name.expected" >&2
    printf 'original:' >&2
    od -An -tx1 "$WORK_DIR/original-$name.stdout" >&2
    exit 1
  fi
  echo "PASS[original/$name]: exact expected stdout"
done

parent_json_red=0
for name in "${cases[@]}"; do
  if compile_and_run parent "$PARENT_COMPILER" "$name"; then
    if cmp -s "$WORK_DIR/original-$name.stdout" "$WORK_DIR/parent-$name.stdout"; then
      echo "PASS[parent/$name]: matches original"
    else
      echo "RED[parent/$name]: stdout differs from original" >&2
      printf 'original:' >&2
      od -An -tx1 "$WORK_DIR/original-$name.stdout" >&2
      printf 'parent:  ' >&2
      od -An -tx1 "$WORK_DIR/parent-$name.stdout" >&2
      if [[ "$name" == json_escape_read ]]; then
        parent_json_red=1
      fi
    fi
  else
    echo "RED[parent/$name]: parent compiler rejected or failed the fixture" >&2
    if [[ "$name" == json_escape_read ]]; then
      parent_json_red=1
    fi
  fi
done
if [[ "$parent_json_red" -ne 1 ]]; then
  echo "FAIL[parent]: expected JSON::Builder::Escape#read mismatch was not reproduced" >&2
  exit 1
fi

for name in "${cases[@]}"; do
  compile_and_run fixed "$FIXED_COMPILER" "$name"
  assert_matches_original fixed "$name"
  echo "PASS[fixed/$name]: exact original stdout"
done

echo 'PASS[json-escape-read-noreturn]: original-first bytes; parent JSON read RED; fixed JSON, typed IO, and virtual bottom guard GREEN'
