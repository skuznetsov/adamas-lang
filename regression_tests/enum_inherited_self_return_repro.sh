#!/usr/bin/env bash
# Inherited Enum :self returns keep their concrete nominal identity before
# lazy lowering, including distinct carriers, instance methods, and overrides.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"

if [[ -z "$COMPILER" || ! -x "$COMPILER" ]]; then
  echo "ERROR: usage: $0 <candidate-compiler>" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" || ! -x "$ORIGINAL_CRYSTAL_BIN" || ! -d "$CRYSTAL_STDLIB" ]]; then
  echo "ERROR: safe runner, original Crystal, or original stdlib is unavailable" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum-inherited-self-return.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_work=$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
abstract struct Enum
  def self.inherited_self_probe : self
    self.new(1)
  end
  def inherited_instance_probe : self
    self
  end
end

enum NarrowInheritedReturn : UInt8
  One = 1
end
enum WideInheritedReturn : UInt64
  One = 1
end
enum OverriddenInheritedReturn
  One = 1
  def self.inherited_self_probe : Int32
    73
  end
end

lib EnumSelfProbeOutput
  fun exit(status : Int32) : NoReturn
  fun putchar(value : Int32) : Int32
end

def choose_narrow(value : NarrowInheritedReturn) : Int32
  42
end
def choose_narrow(value : Enum) : Int32
  77
end
def choose_wide(value : WideInheritedReturn) : Int32
  43
end
def choose_wide(value : Enum) : Int32
  78
end

narrow = NarrowInheritedReturn.inherited_self_probe
wide = WideInheritedReturn.inherited_self_probe
EnumSelfProbeOutput.exit(81) unless choose_narrow(narrow) == 42
EnumSelfProbeOutput.exit(82) unless choose_wide(wide) == 43
EnumSelfProbeOutput.exit(83) unless choose_wide(narrow) == 78
EnumSelfProbeOutput.exit(84) unless choose_narrow(wide) == 77
EnumSelfProbeOutput.exit(85) unless choose_wide(wide.inherited_instance_probe) == 43
EnumSelfProbeOutput.exit(86) unless OverriddenInheritedReturn.inherited_self_probe == 73
EnumSelfProbeOutput.putchar(42)
EnumSelfProbeOutput.putchar(10)
CRYSTAL

run_build() {
  local name="$1"
  shift
  local log="$WORK_DIR/$name.build.log"
  local status=0
  "$@" >"$log" 2>&1 || status=$?
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL: $name compile exited $status" >&2
    cat "$log" >&2
    return 1
  fi
}

run_program() {
  local name="$1"
  local binary="$2"
  local log="$WORK_DIR/$name.run.log"
  local status=0
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$name.run.resources.json" \
    "$SAFE_RUNNER" "$binary" 10 512 >"$log" 2>&1 || status=$?
  if [[ "$status" -ne 0 ]] || ! grep -Fq '[EXIT: 0]' "$log"; then
    echo "FAIL: $name runtime exited $status" >&2
    cat "$log" >&2
    return 1
  fi
  sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/{/^=== STDOUT ===$/d;/^=== STDERR ===$/d;p;}' \
    "$log" >"$WORK_DIR/$name.stdout"
}

run_build original env CRYSTAL_PATH="$CRYSTAL_STDLIB" \
  CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/original.build.resources.json" \
  "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build \
  "$WORK_DIR/probe.cr" -o "$WORK_DIR/original.bin" \
  --link-flags=-fuse-ld=/usr/bin/ld

run_build candidate env CRYSTAL_PATH="$CRYSTAL_STDLIB" \
  ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
  ADAMAS_LLVM_CACHE=0 \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate.build.resources.json" \
  "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/probe.cr" \
  --no-prelude --no-ast-cache --no-llvm-cache -o "$WORK_DIR/candidate.bin"

run_program original "$WORK_DIR/original.bin"
run_program candidate "$WORK_DIR/candidate.bin"

printf '*\n' >"$WORK_DIR/expected.stdout"
if ! diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/original.stdout"; then
  echo "FAIL: original Crystal did not match the expected enum return output" >&2
  exit 1
fi
if ! diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"; then
  echo "FAIL: candidate output differs from original Crystal" >&2
  exit 1
fi

echo "PASS: inherited Enum self returns retain concrete overload identity"
