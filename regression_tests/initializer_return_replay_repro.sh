#!/usr/bin/env bash
# A retired initializer keeps its exact source identity and rebuilds its result.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal || true)}}"
FIXTURE="$ROOT_DIR/spec/fixtures/initializer_return_replay/captured_initializer_result.cr"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/initializer-return-replay.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
[[ -x "$SAFE_RUNNER" && -x "$ADAMAS_BIN" && -x "$CRYSTAL_BIN" ]] || {
  echo 'missing safe runner or compiler' >&2
  exit 2
}
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
printf 'A\n' >"$WORK_DIR/expected"
for mode in stock lazy eager; do
  binary="$WORK_DIR/$mode.bin"
  if [[ "$mode" == stock ]]; then
    flags=()
    if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then flags+=("--link-flags=$ORIGINAL_LINK_FLAGS"); fi
    command=("$SAFE_RUNNER" "$CRYSTAL_BIN" 60 4096 build --prelude=empty
      --no-debug --error-trace "${flags[@]}" "$FIXTURE" -o "$binary")
  else
    command=("$SAFE_RUNNER" "$ADAMAS_BIN" 60 8192 "$FIXTURE"
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary")
    if [[ "$mode" == eager ]]; then
      command=(env ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "${command[@]}")
    fi
  fi
  if ! "${command[@]}" >"$WORK_DIR/build.log" 2>&1; then
    cat "$WORK_DIR/build.log" >&2
    exit 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
       >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log"; then
    cat "$WORK_DIR/run.log" >&2
    exit 1
  fi
  diff -u "$WORK_DIR/expected" "$WORK_DIR/actual"
  printf 'PASS: %s initializer result replay native control\n' "$mode"
done
