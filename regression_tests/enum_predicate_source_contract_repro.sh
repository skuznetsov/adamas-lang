#!/usr/bin/env bash
# Keep source enum predicates consistent across AST call shapes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/enum_predicate_source_contract"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum_predicate_source_contract.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT

if [[ ! -x "$SAFE" || ! -x "$COMPILER" ]]; then
  echo "ERROR: safe runner or compiler is unavailable" >&2
  exit 2
fi

for mode in lazy eager; do
  env_args=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    env_args+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi

  for name in identifier_calls explicit_empty_calls flags_custom_predicate_override flags_none_all_combined plain_enum_none_implicit explicit_none; do
    binary="$WORK_DIR/$name.$mode"
    if ! env "${env_args[@]}" "$SAFE" "$COMPILER" 60 8192 \
        "$FIXTURES/$name.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
        -o "$binary" >"$WORK_DIR/build.log" 2>&1; then
      cat "$WORK_DIR/build.log" >&2
      echo "FAIL: enum predicates did not compile ($name, $mode HIR)" >&2
      exit 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 5 512 \
        >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log"; then
      cat "$WORK_DIR/run.log" >&2
      exit 1
    fi
    if ! cmp -s "$FIXTURES/$name.expected" "$WORK_DIR/actual"; then
      echo "FAIL: enum predicate output differs ($name, $mode HIR)" >&2
      od -An -tx1 "$WORK_DIR/actual" >&2
      exit 1
    fi
  done

  for name in unknown_predicate_rejected unknown_bare flags_all_question_unknown plain_auto_all_rejected unknown_flag_constant_rejected undefined_known_predicate undefined_known_size member_spelling auto_spelling; do
    case "$name" in
      flags_all_question_unknown|undefined_known_predicate) diagnostic='all?' ;;
      undefined_known_size) diagnostic='size' ;;
      member_spelling) diagnostic='ExactCaseFlags::READ' ;;
      auto_spelling) diagnostic='ExactCaseFlags::ALL' ;;
      plain_auto_all_rejected) diagnostic='PlainOnly::All' ;;
      unknown_flag_constant_rejected) diagnostic='FlagsOnly::Undeclared' ;;
      *) diagnostic='not_declared?' ;;
    esac
    status=0
    env "${env_args[@]}" "$SAFE" "$COMPILER" 60 8192 \
      "$FIXTURES/$name.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$WORK_DIR/$name.$mode" >"$WORK_DIR/rejected.log" 2>&1 || status=$?
    if [[ "$status" != 1 ]] || ! grep -Fq "$diagnostic" "$WORK_DIR/rejected.log"; then
      cat "$WORK_DIR/rejected.log" >&2
      echo "FAIL: unknown enum predicate was not diagnosed ($name, $mode HIR)" >&2
      exit 1
    fi
  done
done

echo "PASS: source enum predicates preserve flags semantics and reject unknown names"
