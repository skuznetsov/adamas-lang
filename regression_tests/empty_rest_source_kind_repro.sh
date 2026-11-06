#!/usr/bin/env bash
# ABI-only empty rest packing must preserve source kinds and failed admission.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/empty_rest_source_kind"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/empty-rest-source-kind.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache-*
  if [[ "$status" == 0 && "${KEEP_TMP:-0}" != 1 ]]; then
    rm -rf -- "$WORK_DIR"
  else
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  fi
}
trap cleanup EXIT
[[ -x "$COMPILER" && -x "$ORIGINAL" && -x "$SAFE_RUNNER" ]]
export ADAMAS_LLVM_CACHE=0
original_link_flags="${ORIGINAL_CRYSTAL_LINK_FLAGS:-}"
if [[ "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
  original_link_flags="${original_link_flags:--fuse-ld=/usr/bin/ld}"
fi
cases=(class_first instance_first pre_materialized ordinary_rest repeated_calls source_splat no_overload wrong_instance)
expected=(A A AA BB AIAI C)
for phase in original candidate; do
  for index in "${!cases[@]}"; do
    test_case="${cases[$index]}"
    cache="$WORK_DIR/cache-$phase-$test_case"
    mkdir "$cache"
    output="$WORK_DIR/$phase-$test_case"
    log="$output.build.log"
    if [[ "$phase" == original ]]; then
      args=(build --prelude=empty --no-debug --error-trace)
      [[ -z "$original_link_flags" ]] || args+=("--link-flags=$original_link_flags")
      args+=("$FIXTURES/$test_case.cr")
      tool="$ORIGINAL"
    else
      args=("$FIXTURES/$test_case.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
      tool="$COMPILER"
    fi
    status=0
    CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUNNER" "$tool" 180 8192 \
      "${args[@]}" -o "$output" >"$log" 2>&1 || status=$?
    if [[ "$test_case" == no_overload || "$test_case" == wrong_instance ]]; then
      if [[ "$status" != 1 || -e "$output" ]] || ! grep -Eq 'no overload matches|expected argument.*Int32' "$log"; then
        cat "$log" >&2
        exit 1
      fi
      continue
    fi
    if [[ "$status" != 0 ]]; then
      cat "$log" >&2
      exit 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$output" 5 512 \
        >"$output.stdout" 2>"$output.run.log"; then
      cat "$output.run.log" >&2
      exit 1
    fi
    printf '%s\n' "${expected[$index]}" >"$WORK_DIR/expected.stdout"
    diff -u "$WORK_DIR/expected.stdout" "$output.stdout"
  done
done
echo 'PASS: empty rest packing preserves source kinds and rejection'
