#!/usr/bin/env bash
# Runtime self is a flow-sensitive binding just like a local is_a? receiver.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/self_is_a_narrowing"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/self_is_a_narrowing.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT

if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in metaclass_control metaclass_direct_inherited metaclass_alias_inherited; do
    if ! "$SAFE" "$CRYSTAL_BIN" 60 4096 build --prelude=empty \
        "$FIXTURES/$name.cr" -o "$WORK_DIR/$name.original" \
        >"$WORK_DIR/original-build.log" 2>&1; then
      cat "$WORK_DIR/original-build.log" >&2
      echo "FAIL: original Crystal rejected $name fixture" >&2
      exit 1
    fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK_DIR/$name.original" 5 512 \
      >"$WORK_DIR/original-actual" 2>"$WORK_DIR/original-run.log"
    cmp "$FIXTURES/$name.expected" "$WORK_DIR/original-actual"
  done
else
  echo 'SKIP: no original Crystal binary found; metaclass baselines are not qualified' >&2
fi

for mode in lazy eager; do
  env_args=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    env_args+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi
  for name in guarded_self local_control metaclass_control metaclass_direct_inherited metaclass_alias_inherited; do
    binary="$WORK_DIR/$name.$mode"
    if ! env "${env_args[@]}" "$SAFE" "$COMPILER" 60 8192 \
        "$FIXTURES/$name.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
        -o "$binary" >"$WORK_DIR/build.log" 2>&1; then
      cat "$WORK_DIR/build.log" >&2
      exit 1
    fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 5 512 \
      >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log"
    cmp "$FIXTURES/$name.expected" "$WORK_DIR/actual"
  done
  for name in unguarded_rejected scope_escape_rejected wrong_or_branch_rejected metaclass_instance_only_rejected; do
    status=0
    env "${env_args[@]}" "$SAFE" "$COMPILER" 60 8192 \
      "$FIXTURES/$name.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$WORK_DIR/$name.$mode" >"$WORK_DIR/rejected.log" 2>&1 || status=$?
    expected_symbol=child_only
    [[ "$name" == metaclass_instance_only_rejected ]] && expected_symbol=instance_only
    if [[ "$status" != 1 ]] || ! grep -Fq "$expected_symbol" "$WORK_DIR/rejected.log"; then
      cat "$WORK_DIR/rejected.log" >&2
      echo "FAIL: unproven self call was not rejected ($name, $mode HIR)" >&2
      exit 1
    fi
  done
done
echo 'PASS: self is_a? narrows only the proven control-flow region'
