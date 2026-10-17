#!/usr/bin/env bash
# Discard assignments evaluate their RHS without creating a readable local.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/discard_assignment_contract"
SAFE="${ADAMAS_RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
if [[ -z "${CRYSTAL_PATH:-}" && -d "$ROOT_DIR/../crystal/src" ]]; then
  export CRYSTAL_PATH="$ROOT_DIR/../crystal/src"
fi
[[ -x "$SAFE" && -x "$COMPILER" && -n "$ORIGINAL" && -x "$ORIGINAL" ]] || {
  printf 'missing executable: safe=%s candidate=%s original=%s\n' "$SAFE" "$COMPILER" "$ORIGINAL" >&2
  exit 2
}
WORK="$(mktemp -d "${TMPDIR:-/tmp}/discard-assignment-contract.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK/original.cache" "$WORK/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT
cat >"$WORK/run_program" <<'SH'
#!/usr/bin/env bash
exec "$1" 2>"$2"
SH
chmod +x "$WORK/run_program"
positives=(
  discard_rhs_once
  wildcard_after_discard
  tuple_discard_rhs_once
  tuple_splat_discard
  conditional_discard_wildcard
  nested_array_wildcard
  if_assignment_discard
  tuple_first_discard_rhs_once
  discard_assignment_value
)
negative=discarded_read
compile() {
  local stage="$1"
  local case_name="$2"
  local output="$WORK/$stage.$case_name.bin"
  local -a args
  if [[ "$stage" == original ]]; then
    args=(build "$FIXTURES/$case_name.cr" --single-module --no-debug -o "$output")
    if [[ "$(uname -s)" == Darwin ]]; then
      args+=(--link-flags=-fuse-ld=/usr/bin/ld)
    fi
    env CRYSTAL_CACHE_DIR="$WORK/original.cache" "$SAFE" "$ORIGINAL" 120 8192 \
      "${args[@]}" >"$WORK/$stage.$case_name.compile.log" 2>&1
  else
    env CRYSTAL_CACHE_DIR="$WORK/candidate.cache" ADAMAS_LLVM_CACHE=0 \
      "$SAFE" "$COMPILER" 120 8192 "$FIXTURES/$case_name.cr" --no-prelude \
      --no-debug --no-ast-cache --no-llvm-cache -o "$output" \
      >"$WORK/$stage.$case_name.compile.log" 2>&1
  fi
}
run_positive() {
  local stage="$1"
  local case_name="$2"
  local binary="$WORK/$stage.$case_name.bin"
  local stderr_file="$WORK/$stage.$case_name.stderr"
  if ! compile "$stage" "$case_name"; then
    printf 'FAIL %s compile %s\n' "$stage" "$case_name" >&2
    tail -40 "$WORK/$stage.$case_name.compile.log" >&2
    exit 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 10 512 \
    "$binary" "$stderr_file" >"$WORK/$stage.$case_name.stdout" \
    2>"$WORK/$stage.$case_name.run.log"; then
    printf 'FAIL %s runtime %s\n' "$stage" "$case_name" >&2
    cat "$WORK/$stage.$case_name.run.log" >&2
    exit 1
  fi
  if [[ -s "$stderr_file" ]]; then
    printf 'FAIL %s runtime stderr %s\n' "$stage" "$case_name" >&2
    cat "$stderr_file" >&2
    exit 1
  fi
  if ! cmp "$FIXTURES/expected/$case_name.stdout" "$WORK/$stage.$case_name.stdout"; then
    printf 'FAIL %s stdout %s\n' "$stage" "$case_name" >&2
    od -An -tx1c "$WORK/$stage.$case_name.stdout" >&2
    exit 1
  fi
}
expect_read_rejection() {
  local stage="$1"
  local output="$WORK/$stage.$negative.bin"
  local log="$WORK/$stage.$negative.compile.log"
  local status=0
  compile "$stage" "$negative" || status=$?
  if [[ "$status" -ne 1 || -e "$output" ]]; then
    printf 'FAIL %s expected compile rejection for %s, status=%s\n' "$stage" "$negative" "$status" >&2
    tail -40 "$log" >&2
    exit 1
  fi
  if ! grep -Eiq "can't read from _|undefined local variable|can't use _" "$log"; then
    printf 'FAIL %s missing discard-read diagnostic\n' "$stage" >&2
    cat "$log" >&2
    exit 1
  fi
}
# Qualify every expected byte sequence and the strict negative on original first.
for case_name in "${positives[@]}"; do
  run_positive original "$case_name"
done
expect_read_rejection original
for case_name in "${positives[@]}"; do
  run_positive candidate "$case_name"
done
expect_read_rejection candidate
printf 'PASS[discard-assignment-contract]: original-first discard, tuple, condition, value, and read-rejection cases\n'
