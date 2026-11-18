#!/usr/bin/env bash
# Named admission and emission retain the same source kinds and selected target.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/named_source_argument_kind"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-source-argument-kind.XXXXXX")"
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
cases=(
  positive_class_only reordered_equal_carriers
  instance_first_top_level class_first_top_level absolute_named_top_level
  nested_named_top_level reordered_instance_first
  ordinary_named_specialization
  reject_named_instance reject_named_mixed_kind reject_instance_specialization
)
for phase in original candidate; do
  for test_case in "${cases[@]}"; do
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
    case "$test_case" in
      reject_*)
        if [[ "$status" != 1 || -e "$output" ]] || ! grep -Eq 'no overload matches|expected argument.*Int32' "$log"; then
          cat "$log" >&2
          exit 1
        fi
        continue
        ;;
    esac
    if [[ "$status" != 0 ]]; then
      cat "$log" >&2
      exit 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$output" 5 512 \
        >"$output.stdout" 2>"$output.run.log"; then
      cat "$output.run.log" >&2
      exit 1
    fi
    expected=A
    if [[ "$test_case" == ordinary_named_specialization ]]; then
      expected=ACCAACCA
    fi
    printf '%s\n' "$expected" >"$WORK_DIR/expected.stdout"
    diff -u "$WORK_DIR/expected.stdout" "$output.stdout"
  done
done
echo 'PASS: named arguments preserve source value kinds and selected targets'
