#!/usr/bin/env bash
# Literal NamedTuple indexes must select each union layout and preserve optional Nil.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -x "$SAFE_RUNNER" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "usage: $0 <candidate-compiler>" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-tuple-union-literal-index.XXXXXX")"
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

cp "$ROOT_DIR/regression_tests/fixtures/named_tuple_union_literal_index.cr" "$WORK_DIR/probe.cr"

compile_and_run() {
  local producer="$1"
  local compiler="$2"
  shift 2
  local bin="$WORK_DIR/$producer.bin"
  local cache_dir="$WORK_DIR/$producer.cache"
  local compile_log="$WORK_DIR/$producer.compile.log"
  local run_log="$WORK_DIR/$producer.run.log"
  local status=0

  mkdir -p "$cache_dir"
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$WORK_DIR/probe.cr" --no-debug \
      -o "$bin" --link-flags=-fuse-ld=/usr/bin/ld >"$compile_log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$WORK_DIR/probe.cr" --no-prelude \
      --no-ast-cache --no-llvm-cache -o "$bin" >"$compile_log" 2>&1 || status=$?
  fi
  if [[ "$status" != 0 ]]; then
    cat "$compile_log" >&2
    return "$status"
  fi

  status=0
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.run.resources" \
    "$SAFE_RUNNER" "$bin" 15 512 >"$run_log" 2>&1 || status=$?
  if [[ "$status" != 0 ]] || ! grep -Fq '[EXIT: 0]' "$run_log"; then
    cat "$run_log" >&2
    return 1
  fi
}

compile_and_run original "$ORIGINAL_CRYSTAL_BIN"
compile_and_run candidate "$COMPILER"
cat > "$WORK_DIR/missing.cr" <<'CRYSTAL'
alias RequiredMetric = NamedTuple(value: Int32) | NamedTuple(value: Int64, label: Int32)
def read_required(metric : RequiredMetric)
  metric[:label]
end
read_required({value: 1})
CRYSTAL

for producer in original candidate; do
  status=0
  log="$WORK_DIR/$producer.missing.log"
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/missing.cr" --no-debug \
      -o "$WORK_DIR/missing.original" --link-flags=-fuse-ld=/usr/bin/ld >"$log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/missing.cr" --no-prelude \
      --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/missing.candidate" >"$log" 2>&1 || status=$?
  fi
  if [[ "$status" == 0 ]] || ! grep -Fq "missing key 'label'" "$log"; then
    cat "$log" >&2
    exit 1
  fi
done
printf 'PASS: original and candidate agree on 22 literal NamedTuple checks and reject a missing required key\n'
