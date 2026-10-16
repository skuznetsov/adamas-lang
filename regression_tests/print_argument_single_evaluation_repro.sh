#!/usr/bin/env bash
# Evaluate direct puts/print arguments once and use their lowered HIR result types.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/print-argument-once.XXXXXX")"
cleanup() {
  local status=$?
  for name in union_puts union_print nil_result void_result no_return scalar_width; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/union_puts.cr" <<'CRYSTAL'
def tagged(flag : Bool) : Int32 | String
  puts "effect-union"
  flag ? 1 : "value-union"
end
puts tagged(false)
puts tagged(true)
CRYSTAL
printf '%s' 'effect-union
value-union
effect-union
1
' >"$WORK_DIR/union_puts.expected"

cat >"$WORK_DIR/union_print.cr" <<'CRYSTAL'
def tagged(flag : Bool) : Int32 | String
  puts "effect-print"
  flag ? 1 : "value-print"
end
print tagged(false)
CRYSTAL
printf '%s' 'effect-print
value-print' >"$WORK_DIR/union_print.expected"

cat >"$WORK_DIR/nil_result.cr" <<'CRYSTAL'
def nil_effect
  puts "effect-nil"
  nil
end
puts nil_effect
puts "after-nil"
CRYSTAL
printf '%s' 'effect-nil

after-nil
' >"$WORK_DIR/nil_result.expected"

cat >"$WORK_DIR/void_result.cr" <<'CRYSTAL'
lib LibC
  fun free(pointer : Void*) : Void
end
def void_effect
  puts "effect-void"
  LibC.free(Pointer(Void).null)
end
puts void_effect
puts "after-void"
CRYSTAL
printf '%s' 'effect-void

after-void
' >"$WORK_DIR/void_result.expected"

cat >"$WORK_DIR/no_return.cr" <<'CRYSTAL'
def never : NoReturn
  puts "effect-never"
  raise "halt"
end
begin
  puts never
rescue
  puts "rescued"
end
CRYSTAL
printf '%s' 'effect-never
rescued
' >"$WORK_DIR/no_return.expected"

cat >"$WORK_DIR/scalar_width.cr" <<'CRYSTAL'
def wide_value
  puts "effect-wide"
  17_i64
end
puts wide_value
CRYSTAL
printf '%s' 'effect-wide
17
' >"$WORK_DIR/scalar_width.expected"

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
      --no-debug -o "$output" >"$log" 2>&1; then
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
}

for name in union_puts union_print nil_result void_result no_return scalar_width; do
  compile_run "$name" original "$ORIGINAL_CRYSTAL_BIN"
  compile_run "$name" candidate "$COMPILER"
  echo "PASS[$name]: original and candidate values and effect counts agree"
done
echo "PASS[print-argument-once]: six original-first fixtures agree"
