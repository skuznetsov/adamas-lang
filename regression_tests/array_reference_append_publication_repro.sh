#!/usr/bin/env bash
# Retain class references published by synthesized Array#<< bodies.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array-reference-append.XXXXXX")"
cleanup() {
  local status=$?
  for name in direct growth scalar; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/direct.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

class AppendReferenceCell
  @value : Int32

  def initialize(@value : Int32)
  end

  def value : Int32
    @value
  end

  def value=(value : Int32)
    @value = value
  end
end

cell = AppendReferenceCell.new(65)
values = [] of AppendReferenceCell | Nil
values << cell
cell.value = 66
stored = values[0]
if stored.is_a?(AppendReferenceCell) && stored.value == 66
  C.putchar(65)
else
  C.putchar(88)
end
C.putchar(10)
CRYSTAL
printf 'A\n' >"$WORK_DIR/direct.expected"
: >"$WORK_DIR/direct.stderr.expected"

cat >"$WORK_DIR/growth.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

class GrowthAppendReferenceCell
  @value : Int32

  def initialize(@value : Int32)
  end

  def value : Int32
    @value
  end

  def value=(value : Int32)
    @value = value
  end
end

def append_fresh_after_full(values : Array(GrowthAppendReferenceCell | Nil))
  fresh = GrowthAppendReferenceCell.new(66)
  values << fresh
  fresh.value = 67
end

values = [] of GrowthAppendReferenceCell | Nil
values << GrowthAppendReferenceCell.new(1)
values << GrowthAppendReferenceCell.new(2)
values << GrowthAppendReferenceCell.new(3)
values << GrowthAppendReferenceCell.new(4)
append_fresh_after_full(values)

stored = values[4]
if stored.is_a?(GrowthAppendReferenceCell) && stored.value == 67
  C.putchar(65)
else
  C.putchar(88)
end
C.putchar(10)
CRYSTAL
printf 'A\n' >"$WORK_DIR/growth.expected"
: >"$WORK_DIR/growth.stderr.expected"

cat >"$WORK_DIR/scalar.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end
values = [] of Int32
values << 1
values << 2
values << 3
values << 4
values << 5
if values[0] == 1 && values[4] == 5
  C.putchar(65)
else
  C.putchar(88)
end
C.putchar(10)
CRYSTAL
printf 'A\n' >"$WORK_DIR/scalar.expected"
: >"$WORK_DIR/scalar.stderr.expected"

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
for name in direct growth scalar; do
  compile_run "$name" original "$ORIGINAL_CRYSTAL_BIN"
done
for name in direct growth scalar; do
  compile_run "$name" candidate "$COMPILER"
  echo "PASS[$name]: original and candidate stdout and stderr agree"
done
echo "PASS[array-reference-append]: three original-first fixtures agree"
