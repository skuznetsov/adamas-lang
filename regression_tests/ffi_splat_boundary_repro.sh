#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAMAS_ROOT="${ADAMAS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FIXTURE_DIR="$SCRIPT_DIR/ffi_splat_boundary"
SAFE="${ADAMAS_RUN_SAFE:-$ADAMAS_ROOT/scripts/run_safe.sh}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
case "${1:-}" in
  --original-only)
    [[ "$#" -eq 1 ]] || { echo 'usage: $0 [--original-only | [--candidate] COMPILER]' >&2; exit 2; }
    CANDIDATE=""
    ;;
  --candidate)
    [[ "$#" -eq 2 && -n "$2" ]] || { echo 'usage: $0 [--candidate] COMPILER' >&2; exit 2; }
    CANDIDATE="$2"
    ;;
  "")
    CANDIDATE="${ADAMAS_BIN:-$ADAMAS_ROOT/bin/adamas}"
    ;;
  -* )
    echo 'usage: $0 [--original-only | [--candidate] COMPILER]' >&2
    exit 2
    ;;
  *)
    [[ "$#" -eq 1 ]] || { echo 'usage: $0 [--original-only | [--candidate] COMPILER]' >&2; exit 2; }
    CANDIDATE="$1"
    ;;
esac
PRISTINE_CRYSTAL_PATH="${PRISTINE_CRYSTAL_PATH:-${CRYSTAL_PATH:-$ADAMAS_ROOT/../crystal/src}}"
[[ -d "$PRISTINE_CRYSTAL_PATH" ]] || {
  echo 'set PRISTINE_CRYSTAL_PATH to the pinned original Crystal stdlib' >&2
  exit 2
}
export CRYSTAL_PATH="$PRISTINE_CRYSTAL_PATH"
[[ -x "$SAFE" && -x "$ORIGINAL" ]] || {
  echo 'safe runner and original Crystal must be executable' >&2
  exit 2
}
if [[ -n "$CANDIDATE" && ! -x "$CANDIDATE" ]]; then
  echo "candidate compiler is not executable: $CANDIDATE" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ffi-named-args.XXXXXX")"
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
set -euo pipefail
exec "$1" 2>"$2"
SH
chmod +x "$WORK/run_program"

compile_source() {
  local stage="$1" source="$2" output="$3" log="$4"
  if [[ "$stage" == original ]]; then
    local -a args=(build "$source" --no-debug -o "$output")
    [[ "$(uname -s)" != Darwin ]] || args+=(--link-flags=-fuse-ld=/usr/bin/ld)
    CRYSTAL_CACHE_DIR="$WORK/original.cache" \
      "$SAFE" "$ORIGINAL" 180 8192 "${args[@]}" >"$log" 2>&1
  else
    CRYSTAL_CACHE_DIR="$WORK/candidate.cache" ADAMAS_LLVM_CACHE=0 \
      "$SAFE" "$CANDIDATE" 180 8192 "$source" \
      --no-ast-cache --no-llvm-cache --no-debug --no-prelude -o "$output" \
      >"$log" 2>&1
  fi
}

expect_positive() {
  local stage="$1" name="${2:-valid}" expected_text="${3:-$'A\nB\n'}"
  local output="$WORK/$stage.$name.bin"
  local compile_log="$WORK/$stage.$name.compile.log"
  local stdout="$WORK/$stage.$name.stdout"
  local stderr="$WORK/$stage.$name.stderr"
  local runner_log="$WORK/$stage.$name.runner.log"
  local expected="$WORK/$name.expected.stdout"

  if ! compile_source "$stage" "$FIXTURE_DIR/$name.cr" "$output" "$compile_log"; then
    echo "FAIL: $stage rejected valid named-extern calls" >&2
    tail -50 "$compile_log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 15 1024 \
    "$output" "$stderr" >"$stdout" 2>"$runner_log"; then
    echo "FAIL: $stage named-extern executable failed" >&2
    cat "$stderr" >&2
    cat "$runner_log" >&2
    return 1
  fi
  printf '%s' "$expected_text" >"$expected"
  if ! cmp -s "$expected" "$stdout" || [[ -s "$stderr" ]]; then
    echo "FAIL: $stage named-extern output differs" >&2
    od -An -tx1c "$stdout" >&2
    [[ ! -s "$stderr" ]] || cat "$stderr" >&2
    return 1
  fi
}

expect_rejection() {
  local stage="$1" name="$2" marker="$3"
  local source="$FIXTURE_DIR/$name.cr"
  local output="$WORK/$stage.$name.bin"
  local compile_log="$WORK/$stage.$name.compile.log"
  local status=0

  compile_source "$stage" "$source" "$output" "$compile_log" || status=$?
  if [[ "$status" -ne 1 || -e "$output" ]]; then
    echo "FAIL: $stage must reject $name with rc=1 and no executable, got rc=$status" >&2
    tail -50 "$compile_log" >&2
    return 1
  fi
  if ! grep -Fq "$marker" "$compile_log"; then
    echo "FAIL: $stage rejection for $name lacks marker: $marker" >&2
    tail -50 "$compile_log" >&2
    return 1
  fi
}

run_matrix() {
  local stage="$1"
  expect_positive "$stage"
  expect_positive "$stage" splat_order $'B\nC\nAD\n'
  expect_rejection "$stage" duplicate "argument for parameter 'fd' already specified"
  expect_rejection "$stage" unknown "no parameter named 'length'"
  expect_rejection "$stage" missing 'missing argument: count'
  expect_rejection "$stage" variadic "can't use named args with variadic function"
}

run_matrix original
[[ -z "$CANDIDATE" ]] || run_matrix candidate
echo 'PASS: original-first named extern argument order and validation'
