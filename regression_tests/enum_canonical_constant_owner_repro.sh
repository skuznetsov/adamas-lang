#!/usr/bin/env bash
# A resolved enum constant owner must survive entry into another namespace.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/enum_canonical_constant_owner"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum_canonical_constant_owner.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT

for mode in lazy eager; do
  env_args=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    env_args+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi
  binary="$WORK_DIR/shadowed_namespace.$mode"
  if ! env "${env_args[@]}" "$SAFE" "$COMPILER" 60 8192 \
      "$FIXTURES/shadowed_namespace.cr" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$binary" >"$WORK_DIR/build.log" 2>&1; then
    cat "$WORK_DIR/build.log" >&2
    exit 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 5 512 \
    >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log"
  cmp "$FIXTURES/shadowed_namespace.expected" "$WORK_DIR/actual"
  for name in borrowed_member_rejected member_spelling_rejected nonflags_all_rejected; do
    case "$name" in
      borrowed_member_rejected) diagnostic='Registry::Kind::Other' ;;
      member_spelling_rejected) diagnostic='Registry::Kind::BLOCKDEVICE' ;;
      nonflags_all_rejected) diagnostic='Shadow::Registry::Options::All' ;;
    esac
    status=0
    env "${env_args[@]}" "$SAFE" "$COMPILER" 60 8192 \
      "$FIXTURES/$name.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$WORK_DIR/$name.$mode" >"$WORK_DIR/rejected.log" 2>&1 || status=$?
    if [[ "$status" != 1 ]] || ! grep -Fq "$diagnostic" "$WORK_DIR/rejected.log"; then
      cat "$WORK_DIR/rejected.log" >&2
      echo "FAIL: enum constant rejection differs ($name, $mode HIR)" >&2
      exit 1
    fi
  done
done
echo 'PASS: canonical enum owners survive namespace shadowing'
