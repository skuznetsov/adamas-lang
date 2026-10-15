#!/usr/bin/env bash
# Static module calls with omitted defaults must preserve the selected method's
# inferred return type before the first typed body has been materialized.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:?usage: module_default_argument_return_repro.sh <candidate-compiler>}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-default-return.XXXXXX")"

cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_work=$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/preamble.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32)
end

module DeferredDefault
  def self.value(value = 42)
    value
  end
end
CRYSTAL

run_case() {
  local case_name="$1" expression="$2" expected_exit="$3"
  local source="$WORK_DIR/$case_name.cr"
  printf '%s\n' "$(cat "$WORK_DIR/preamble.cr")" "$expression" >"$source"

  for mode in original candidate; do
    local cache="$WORK_DIR/$mode.cache/$case_name"
    local binary="$WORK_DIR/$mode.$case_name.bin"
    local build_log="$WORK_DIR/$mode.$case_name.build.log"
    local run_log="$WORK_DIR/$mode.$case_name.run.log"
    mkdir -p "$cache"

    if [[ "$mode" == original ]]; then
      if ! CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
        "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" 180 8192 build "$source" \
        --prelude=empty --no-debug --link-flags=-fuse-ld=/usr/bin/ld \
        -o "$binary" >"$build_log" 2>&1; then
        cat "$build_log" >&2
        return 1
      fi
    else
      if ! CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
        ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
        "$SAFE_RUNNER" "$COMPILER" 180 8192 "$source" --no-prelude \
        --no-debug --no-ast-cache --no-llvm-cache -o "$binary" \
        >"$build_log" 2>&1; then
        cat "$build_log" >&2
        return 1
      fi
    fi

    local run_status=0
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 10 512 \
      >"$run_log" 2>&1 || run_status=$?
    if [[ "$run_status" -ne "$expected_exit" ]] ||
      ! grep -q "^\\[EXIT: $expected_exit\\]" "$run_log"; then
      echo "$mode $case_name: expected exit $expected_exit, got status $run_status" >&2
      cat "$run_log" >&2
      return 1
    fi
  done
}

run_case bare_default 'LibC.exit(DeferredDefault.value)' 42
run_case grouped_default 'LibC.exit((DeferredDefault.value))' 42
run_case explicit_empty_call 'LibC.exit(DeferredDefault.value())' 42

echo "module_default_argument_return_repro_ok"
