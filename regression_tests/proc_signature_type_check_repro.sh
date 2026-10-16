#!/usr/bin/env bash
# Compare complete Proc signatures rather than the erased display name.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
[[ -x "$ADAMAS_BIN" && -x "$ORIGINAL_CRYSTAL" && -x "$SAFE_RUNNER" && -d "$CRYSTAL_STDLIB" ]] || exit 2

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proc-signature-check.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib LibC
  fun puts(value : UInt8*) : Int32
end

nil_proc = -> { nil }
int_proc = -> { 1 }
input_proc = ->(item : Int32) { item }
union_proc = ->(item : Int32) { if item.is_a?(Int32); 1; else; "dead"; end }
LibC.puts(nil_proc.is_a?(Proc(Nil | Int32)) ? "true" : "false")
LibC.puts(int_proc.is_a?(Proc(Nil)) ? "true" : "false")
LibC.puts(input_proc.is_a?(Proc(Int32 | Int64, Int32)) ? "true" : "false")
LibC.puts(input_proc.is_a?(Proc(Int64, Int32)) ? "true" : "false")
LibC.puts(nil_proc.is_a?(Proc(Int32)) ? "true" : "false")
LibC.puts(int_proc.is_a?(Proc(String)) ? "true" : "false")
LibC.puts(input_proc.is_a?(Proc(Int32)) ? "true" : "false")
LibC.puts(input_proc.is_a?(Proc) ? "true" : "false")
LibC.puts(union_proc.is_a?(Proc(Int32, Int32)) ? "true" : "false")
LibC.puts(nil_proc.is_a?(Proc(Nil)) ? "true" : "false")
LibC.puts(int_proc.is_a?(Proc(Int32)) ? "true" : "false")
LibC.puts(input_proc.is_a?(Proc(Int32, Int32)) ? "true" : "false")
LibC.puts(union_proc.is_a?(Proc(Int32, Int32 | String)) ? "true" : "false")
def bare_proc(value : Proc(Int32) | Proc(Int64)) : Bool
  value.is_a?(Proc)
end

def exact_proc(value : Proc(Int32) | Proc(Int64)) : Bool
  value.is_a?(Proc(Int32))
end

def absent_proc(value : Proc(Int32) | Proc(Int64)) : Bool
  value.is_a?(Proc(String))
end

def mixed_proc(value : Proc(Nil) | Tuple(Int32, Int32)) : Bool
  value.is_a?(Proc)
end

small = -> { 1 }
wide = -> { 1_i64 }
empty = -> { nil }
pair = {1, 2}
LibC.puts(bare_proc(small) ? "true" : "false")
LibC.puts(bare_proc(wide) ? "true" : "false")
LibC.puts(exact_proc(small) ? "true" : "false")
LibC.puts(exact_proc(wide) ? "true" : "false")
LibC.puts(absent_proc(small) ? "true" : "false")
LibC.puts(absent_proc(wide) ? "true" : "false")
LibC.puts(mixed_proc(empty) ? "true" : "false")
LibC.puts(mixed_proc(pair) ? "true" : "false")
def narrowed_payload(value : Proc(Int32) | Proc(Int64)) : Bool
  if value.is_a?(Proc)
    if value.is_a?(Proc(Int32))
      value.call == 1
    else
      value.call == 2_i64
    end
  else
    false
  end
end

payload_small = -> { 1 }
payload_wide = -> { 2_i64 }
LibC.puts(narrowed_payload(payload_small) ? "true" : "false")
LibC.puts(narrowed_payload(payload_wide) ? "true" : "false")
CRYSTAL

printf 'false\nfalse\nfalse\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\nfalse\nfalse\ntrue\nfalse\ntrue\ntrue\n' >"$WORK_DIR/expected.out"
check_run() {
  local stage="$1"
  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-run.resources" \
      "$SAFE_RUNNER" "$WORK_DIR/$stage" 10 512 >"$WORK_DIR/$stage-run.log" 2>&1; then
    cat "$WORK_DIR/$stage-run.log" >&2
    return 1
  fi
  awk '/^=== STDOUT ===$/{capture=1;next} /^=== STDERR ===$/{exit} capture{print}' \
    "$WORK_DIR/$stage-run.log" >"$WORK_DIR/$stage.out"
  diff -u "$WORK_DIR/expected.out" "$WORK_DIR/$stage.out"
}

env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/original-build.resources" \
  "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" 180 8192 build "$WORK_DIR/probe.cr" \
  -o "$WORK_DIR/original" --link-flags=-fuse-ld=/usr/bin/ld \
  >"$WORK_DIR/original-build.log" 2>&1 || { cat "$WORK_DIR/original-build.log" >&2; exit 1; }
rm -rf "$WORK_DIR/original.cache"
check_run original

env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache" \
  ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate-build.resources" \
  "$SAFE_RUNNER" "$ADAMAS_BIN" 180 8192 "$WORK_DIR/probe.cr" --no-prelude \
  --no-ast-cache --no-llvm-cache -o "$WORK_DIR/candidate" \
  >"$WORK_DIR/candidate-build.log" 2>&1 || { cat "$WORK_DIR/candidate-build.log" >&2; exit 1; }
rm -rf "$WORK_DIR/candidate.cache"
check_run candidate
printf 'PASS: concrete Proc signature predicates match Crystal\n'
