#!/usr/bin/env bash
# Preserve Proc input arity across grouped, nested, union, and zero-input forms.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FIXTURE="$ROOT_DIR/spec/fixtures/grouped_proc_input_types/grouped_proc_input_types.cr"
EXPECTED="$ROOT_DIR/spec/fixtures/grouped_proc_input_types/grouped_proc_input_types.expected"
SPEC_SOURCE="$ROOT_DIR/spec/hir/grouped_proc_input_type_contract_spec.cr"

if [[ -z "${CRYSTAL_PATH:-}" && -d "$ROOT_DIR/../crystal/src" ]]; then
  export CRYSTAL_PATH="$ROOT_DIR/../crystal/src"
fi
ORIGINAL_CRYSTAL_PATH="${CRYSTAL_PATH:-}"

if [[ ! -x "$SAFE" || ! -x "$COMPILER" || ! -x "$ORIGINAL" ]]; then
  printf 'required executable missing: safe=%s candidate=%s original=%s\n' \
    "$SAFE" "$COMPILER" "$ORIGINAL" >&2
  exit 2
fi
for required_file in "$FIXTURE" "$EXPECTED" "$SPEC_SOURCE" "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"; do
  if [[ ! -f "$required_file" ]]; then
    printf 'required file missing: %s\n' "$required_file" >&2
    exit 2
  fi
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/grouped-proc-input-types.XXXXXX")"
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$WORK/original.cache" "$WORK/candidate.cache" "$WORK/hir_spec.cache" "$WORK/env.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

if [[ -z "$ORIGINAL_CRYSTAL_PATH" ]]; then
  CRYSTAL_CACHE_DIR="$WORK/env.cache" RUN_SAFE_PASSTHROUGH_STDIO=1 \
    "$SAFE" "$ORIGINAL" 10 1024 env CRYSTAL_PATH \
    >"$WORK/original.crystal_path" 2>"$WORK/original.crystal_path.log"
  ORIGINAL_CRYSTAL_PATH="$(cat "$WORK/original.crystal_path")"
  [[ -n "$ORIGINAL_CRYSTAL_PATH" ]] || { printf 'empty original CRYSTAL_PATH\n' >&2; exit 2; }
  export CRYSTAL_PATH="$ORIGINAL_CRYSTAL_PATH"
fi

compile_original() {
  local source="$1"
  local output="$2"
  local log="$3"
  local cache="$4"
  local status=0
  local args
  args=(build --no-debug "$source" -o "$output")
  if [[ "$(uname -s)" == Darwin ]]; then
    args+=(--link-flags=-fuse-ld=/usr/bin/ld)
  fi
  rm -f -- "$output"
  CRYSTAL_CACHE_DIR="$cache" "$SAFE" "$ORIGINAL" 300 8192 \
    "${args[@]}" >"$log" 2>&1 || status=$?
  if [[ "$status" -ne 0 || ! -x "$output" ]]; then
    printf 'FAIL: pinned Crystal build (rc=%s): %s\n' "$status" "$source" >&2
    tail -n 80 "$log" >&2
    return 1
  fi
}

run_safe_binary() {
  local name="$1"
  local binary="$2"
  local expected="$3"
  local stdout="$WORK/$name.stdout"
  local stderr="$WORK/$name.stderr"
  local clean_stderr="$WORK/$name.stderr.clean"
  local status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 60 1024 >"$stdout" 2>"$stderr" || status=$?
  grep -Ev '^\[EXIT: [0-9]+\] after ~|^\[RUN_SAFE_RESOURCE\]' "$stderr" >"$clean_stderr" || true
  if [[ "$status" -ne 0 ]] || ! cmp -s "$expected" "$stdout" || [[ -s "$clean_stderr" ]]; then
    printf 'FAIL: %s runtime output (rc=%s)\n' "$name" "$status" >&2
    diff -u "$expected" "$stdout" >&2 || true
    tail -n 50 "$clean_stderr" >&2
    return 1
  fi
}

# Qualify accepted syntax and runtime behavior with the pinned original first.
compile_original "$FIXTURE" "$WORK/original.bin" "$WORK/original.build.log" "$WORK/original.cache"
run_safe_binary original "$WORK/original.bin" "$EXPECTED"

# Compile direct HIR helper checks against this checkout's exact source bytes.
mkdir -p "$WORK/spec/hir"
ln -s "$ROOT_DIR/src" "$WORK/src"
cat >"$WORK/spec/spec_helper.cr" <<'SPEC_HELPER'
require "spec"
require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"
SPEC_HELPER
cp "$SPEC_SOURCE" "$WORK/spec/hir/grouped_proc_input_type_contract_spec.cr"
HIR_CRYSTAL_PATH="$WORK/src"
if [[ -n "$ORIGINAL_CRYSTAL_PATH" ]]; then
  HIR_CRYSTAL_PATH="$HIR_CRYSTAL_PATH:$ORIGINAL_CRYSTAL_PATH"
fi
spec_status=0
spec_link_args=()
if [[ "$(uname -s)" == Darwin ]]; then
  spec_link_args+=(--link-flags=-fuse-ld=/usr/bin/ld)
fi
CRYSTAL_PATH="$HIR_CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$WORK/hir_spec.cache" \
  "$SAFE" "$ORIGINAL" 300 8192 build --no-debug "${spec_link_args[@]}" \
  "$WORK/spec/hir/grouped_proc_input_type_contract_spec.cr" \
  -o "$WORK/grouped_proc_input_type_contract_spec" >"$WORK/hir_spec.build.log" 2>&1 || spec_status=$?
if [[ "$spec_status" -ne 0 || ! -x "$WORK/grouped_proc_input_type_contract_spec" ]]; then
  printf 'FAIL: grouped Proc HIR helper spec build (rc=%s)\n' "$spec_status" >&2
  tail -n 80 "$WORK/hir_spec.build.log" >&2
  exit 1
fi
spec_status=0
RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/grouped_proc_input_type_contract_spec" \
  60 1024 >"$WORK/hir_spec.stdout" 2>"$WORK/hir_spec.stderr" || spec_status=$?
grep -Ev '^\[EXIT: [0-9]+\] after ~|^\[RUN_SAFE_RESOURCE\]' "$WORK/hir_spec.stderr" >"$WORK/hir_spec.stderr.clean" || true
if [[ "$spec_status" -ne 0 ]] || ! grep -Eq '6 examples, 0 failures' "$WORK/hir_spec.stdout" || [[ -s "$WORK/hir_spec.stderr.clean" ]]; then
  printf 'FAIL: grouped Proc HIR helper spec (rc=%s)\n' "$spec_status" >&2
  cat "$WORK/hir_spec.stdout" >&2
  tail -n 50 "$WORK/hir_spec.stderr.clean" >&2
  exit 1
fi

# Compare the candidate only after the original's syntax and behavior qualify.
rm -f -- "$WORK/candidate.bin"
candidate_status=0
CRYSTAL_CACHE_DIR="$WORK/candidate.cache" ADAMAS_LLVM_CACHE=0 \
  "$SAFE" "$COMPILER" 300 8192 "$FIXTURE" --no-ast-cache \
  --no-llvm-cache --no-debug -o "$WORK/candidate.bin" \
  >"$WORK/candidate.build.log" 2>&1 || candidate_status=$?
if [[ "$candidate_status" -ne 0 || ! -x "$WORK/candidate.bin" ]]; then
  printf 'FAIL: candidate build (rc=%s)\n' "$candidate_status" >&2
  tail -n 80 "$WORK/candidate.build.log" >&2
  exit 1
fi
run_safe_binary candidate "$WORK/candidate.bin" "$EXPECTED"
cmp -s "$WORK/original.stdout" "$WORK/candidate.stdout"
printf 'PASS[grouped-proc-input-types]: original syntax, 6 HIR examples, and 8 runtime results\n'
