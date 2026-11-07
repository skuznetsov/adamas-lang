#!/usr/bin/env bash
# Block-result forall inference preserves the source kind of each Tuple slot.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="${SAFE_RUNNER:-${ADAMAS_SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}}"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal || true)}}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/block_tuple_forall"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block-tuple-forall.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
[[ -x "$SAFE_RUNNER" && -x "$ADAMAS_BIN" && -x "$CRYSTAL_BIN" ]] || {
  echo 'missing safe runner or compiler' >&2
  exit 2
}
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
export CRYSTAL_CACHE_DIR="$WORK_DIR/cache"
mkdir -p "$CRYSTAL_CACHE_DIR"

compile_case() {
  local mode="$1" source="$2" binary="$3"
  local -a command flags=()
  if [[ "$mode" == stock ]]; then
    local link_flags="${ORIGINAL_LINK_FLAGS:-${ORIGINAL_CRYSTAL_LINK_FLAGS:-}}"
    if [[ -n "$link_flags" ]]; then flags+=("--link-flags=$link_flags"); fi
    command=("$SAFE_RUNNER" "$CRYSTAL_BIN" 60 4096 build --prelude=empty
      --no-debug --error-trace "${flags[@]}" "$source" -o "$binary")
  else
    command=("$SAFE_RUNNER" "$ADAMAS_BIN" 60 8192 "$source"
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary")
    if [[ "$mode" == eager ]]; then
      command=(env ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "${command[@]}")
    fi
  fi
  "${command[@]}"
}

for mode in stock lazy eager; do
  for name in instances class_key class_value nested_class class_local combined base_input lexical_shadow; do
    binary="$WORK_DIR/$mode-$name.bin"
    if ! compile_case "$mode" "$FIXTURES/$name.cr" "$binary" >"$WORK_DIR/build.log" 2>&1; then
      cat "$WORK_DIR/build.log" >&2
      echo "FAIL: $mode $name must compile" >&2
      exit 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
         >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log"; then
      cat "$WORK_DIR/run.log" >&2
      exit 1
    fi
    if [[ "$name" == combined ]]; then
      printf 'ABCDBA\n' >"$WORK_DIR/expected"
    else
      printf 'A\n' >"$WORK_DIR/expected"
    fi
    diff -u "$WORK_DIR/expected" "$WORK_DIR/actual"
    printf 'PASS: %s %s Tuple source-kind binding\n' "$mode" "$name"
  done
  for name in reject_class_key reject_class_value reject_instance_key; do
    binary="$WORK_DIR/$mode-$name.bin"
    set +e
    compile_case "$mode" "$FIXTURES/$name.cr" "$binary" >"$WORK_DIR/reject.log" 2>&1
    status=$?
    set -e
    if [[ "$status" != 1 || -e "$binary" ]] || \
       ! grep -Eq 'expected argument #1|no overload matches accept' "$WORK_DIR/reject.log"; then
      cat "$WORK_DIR/reject.log" >&2
      echo "FAIL: $mode $name must reject the crossed class/instance restriction" >&2
      exit 1
    fi
    printf 'PASS: %s %s rejected by source restriction\n' "$mode" "$name"
  done
done
