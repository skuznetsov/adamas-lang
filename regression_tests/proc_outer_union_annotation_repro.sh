#!/usr/bin/env bash
# Preserve the boundary between a Proc result union and an outer type union.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
[[ -x "$ADAMAS_BIN" && -x "$ORIGINAL_CRYSTAL" && -x "$SAFE_RUNNER" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "usage: ADAMAS_BIN=<compiler> $0" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proc-outer-union.XXXXXX")"
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
lib ProcOuterUnionProbe
  fun puts(message : UInt8*) : Int32
end
alias ProcOuterUnionVariant = Proc(Nil) | Tuple(Int32, Int32)

def direct_proc_outer_union(value : Proc(Nil) | Tuple(Int32, Int32)) : Bool
  value.is_a?(Proc(Nil))
end

def aliased_proc_outer_union(value : ProcOuterUnionVariant) : Bool
  value.is_a?(Proc(Nil))
end

callback = -> { nil }
tuple = {1, 2}
ProcOuterUnionProbe.puts((direct_proc_outer_union(callback) ? "true" : "false").to_unsafe)
ProcOuterUnionProbe.puts((direct_proc_outer_union(tuple) ? "true" : "false").to_unsafe)
ProcOuterUnionProbe.puts((aliased_proc_outer_union(callback) ? "true" : "false").to_unsafe)
ProcOuterUnionProbe.puts((aliased_proc_outer_union(tuple) ? "true" : "false").to_unsafe)
CRYSTAL

check_run() {
  local stage="$1"
  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-run.resources" \
      "$SAFE_RUNNER" "$WORK_DIR/$stage" 10 512 \
      >"$WORK_DIR/$stage-run.log" 2>&1; then
    cat "$WORK_DIR/$stage-run.log" >&2
    return 1
  fi
  awk '/^=== STDOUT ===$/{capture=1;next} /^=== STDERR ===$/{exit} capture{print}' "$WORK_DIR/$stage-run.log" >"$WORK_DIR/$stage.out"
  diff -u "$WORK_DIR/expected.out" "$WORK_DIR/$stage.out" || {
    cat "$WORK_DIR/$stage-run.log" >&2
    return 1
  }
}

env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/original-build.resources" \
  "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" 180 8192 build "$WORK_DIR/probe.cr" \
  -o "$WORK_DIR/original" --link-flags=-fuse-ld=/usr/bin/ld \
  >"$WORK_DIR/original-build.log" 2>&1 || {
    cat "$WORK_DIR/original-build.log" >&2
    exit 1
  }
rm -rf "$WORK_DIR/original.cache"
printf 'true\nfalse\ntrue\nfalse\n' >"$WORK_DIR/expected.out"
check_run original

env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache" \
  ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate-build.resources" \
  "$SAFE_RUNNER" "$ADAMAS_BIN" 180 8192 "$WORK_DIR/probe.cr" --no-prelude \
  --no-ast-cache --no-llvm-cache -o "$WORK_DIR/candidate" \
  >"$WORK_DIR/candidate-build.log" 2>&1 || {
    cat "$WORK_DIR/candidate-build.log" >&2
    exit 1
  }
rm -rf "$WORK_DIR/candidate.cache"
check_run candidate

printf 'PASS: direct and aliased Proc outer unions match Crystal\n'
