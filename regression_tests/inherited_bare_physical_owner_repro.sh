#!/usr/bin/env bash
# Runtime guards for inherited nilary bodies and required-argument siblings.
# The split-arena HIR spec directly detects a stale physical body owner.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-$(command -v crystal || true)}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/inherited_bare_physical_owner"
[[ -x "$ADAMAS_BIN" && -n "$CRYSTAL_BIN" && -x "$CRYSTAL_BIN" ]] || {
  echo "ERROR: set ADAMAS_BIN and CRYSTAL_BIN to executable compilers" >&2
  exit 2
}
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inherited-bare-owner.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

for mode in stock lazy eager; do
  mode_env=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  [[ "$mode" != eager ]] || mode_env+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  for fixture in bare_first sibling_first direct_override module_sibling wrong_result module_wrong_argument; do
    binary="$WORK_DIR/$fixture.$mode"
    log="$binary.compile.log"
    if [[ "$mode" == stock ]]; then
      command=(env "${mode_env[@]}" "$SAFE_RUNNER" "$CRYSTAL_BIN" 120 8192
        build --prelude=empty "$FIXTURES/$fixture.cr" -o "$binary")
    else
      command=(env "${mode_env[@]}" "$SAFE_RUNNER" "$ADAMAS_BIN" 120 8192
        "$FIXTURES/$fixture.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary")
    fi
    compile_status=0
    "${command[@]}" >"$log" 2>&1 || compile_status=$?
    case "$fixture" in
      wrong_result|module_wrong_argument)
        if [[ "$compile_status" != 1 ]] || ! rg -q 'no overload matches|expected .* to be|must be .*not|argument .* must be|incompatible explicit arguments' "$log"; then
          cat "$log" >&2
          echo "FAIL: expected a type error for $fixture ($mode), got $compile_status" >&2
          exit 1
        fi
        continue
        ;;
    esac
    if [[ "$compile_status" != 0 ]]; then
      cat "$log" >&2
      echo "FAIL: $fixture did not compile ($mode)" >&2
      exit 1
    fi
    case "$fixture" in
      bare_first) printf 'AB\n' >"$WORK_DIR/expected" ;;
      sibling_first) printf 'BA\n' >"$WORK_DIR/expected" ;;
      direct_override) printf 'CB\n' >"$WORK_DIR/expected" ;;
      module_sibling) printf 'ABA\n' >"$WORK_DIR/expected" ;;
    esac
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
        >"$binary.stdout" 2>"$binary.run.log"; then
      cat "$binary.run.log" >&2
      echo "FAIL: $fixture did not run ($mode)" >&2
      exit 1
    fi
    if ! cmp -s "$WORK_DIR/expected" "$binary.stdout"; then
      diff -u "$WORK_DIR/expected" "$binary.stdout" >&2 || true
      echo "FAIL: incorrect $fixture output ($mode)" >&2
      exit 1
    fi
  done
done
echo 'PASS: inherited bare owner, sibling order, direct override, module bindings, and type errors'
