#!/usr/bin/env bash
# A primitive is_a? target must remove its exact union arm on the false edge.
# This exercises Bool | Char through a runtime-selected union value so the
# compiler cannot specialize away the branch.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="${SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/primitive-else-narrowing.XXXXXX")"
ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL" ]] || {
  echo "missing run_safe.sh, Adamas compiler, or original Crystal compiler" >&2
  exit 2
}

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
@[Link("c")]
lib PrimitiveElseOutput
  fun putchar(value : Int32) : Int32
end

def selected(flag : Bool) : Bool | Char
  if flag
    false
  else
    'Z'
  end
end

def char_result(value : Char) : Int32
  66
end

def bool_or_char_result(value : Bool | Char) : Int32
  if value.is_a?(Bool)
    65
  else
    char_result(value)
  end
end

PrimitiveElseOutput.putchar(bool_or_char_result(selected(true)))
PrimitiveElseOutput.putchar(bool_or_char_result(selected(false)))
PrimitiveElseOutput.putchar(10)
CRYSTAL
printf 'AB\n' >"$WORK_DIR/expected"

compile_case() {
  local mode="$1" status=0
  local -a env_args command_args
  env_args=()
  if [[ "$mode" == original ]]; then
    command_args=("$ORIGINAL" build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}"
      "$WORK_DIR/probe.cr" -o "$WORK_DIR/$mode.bin")
  else
    command_args=("$COMPILER" "$WORK_DIR/probe.cr" --no-prelude --no-debug
      --no-ast-cache --no-llvm-cache -o "$WORK_DIR/$mode.bin")
    if [[ "$mode" == eager ]]; then
      env_args+=(ADAMAS_EAGER_MONO=1)
    else
      env_args+=(-u ADAMAS_EAGER_MONO)
    fi
  fi
  env_args+=(CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$mode")
  if [[ -n "${CRYSTAL_PATH:-}" ]]; then
    env_args+=(CRYSTAL_PATH="$CRYSTAL_PATH")
  fi
  "$SAFE_RUNNER" env 120 8192 "${env_args[@]}" "${command_args[@]}" \
    >"$WORK_DIR/$mode.compile.log" 2>&1 || status=$?
  if [[ "$status" != 0 ]]; then
    cat "$WORK_DIR/$mode.compile.log" >&2
    return "$status"
  fi
}

run_case() {
  local mode="$1"
  compile_case "$mode"
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/$mode.bin" 5 512 \
    >"$WORK_DIR/$mode.stdout" 2>"$WORK_DIR/$mode.run.log" || {
      cat "$WORK_DIR/$mode.run.log" >&2
      return 1
    }
  diff -u "$WORK_DIR/expected" "$WORK_DIR/$mode.stdout"
  echo "PASS[$mode]: false Bool check narrows union to Char"
}

for mode in original lazy eager; do
  run_case "$mode"
done
