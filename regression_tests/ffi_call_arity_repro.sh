#!/usr/bin/env bash
# Source FFI calls must enforce fixed arity and a variadic function minimum.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
OUT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
FIXTURE_DIR="$SCRIPT_DIR/ffi_call_arity"
ADAMAS_ROOT="${ADAMAS_ROOT:-}"
if [[ -z "$ADAMAS_ROOT" && -x "$OUT_ROOT/../adamas/scripts/run_safe.sh" ]]; then
  ADAMAS_ROOT="$(cd "$OUT_ROOT/../adamas" && pwd -P)"
fi
if [[ -z "$ADAMAS_ROOT" ]]; then
  probe="$SCRIPT_DIR"
  while [[ "$probe" != / ]]; do
    if [[ -x "$probe/scripts/run_safe.sh" && -d "$probe/src/compiler" ]]; then
      ADAMAS_ROOT="$probe"
      break
    fi
    probe="$(dirname "$probe")"
  done
fi
[[ -n "$ADAMAS_ROOT" ]] || {
  echo 'set ADAMAS_ROOT to the Adamas checkout' >&2
  exit 2
}

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ffi-call-arity.XXXXXX")"
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
  local stage="$1" name="$2" source="$3" expected="$4"
  local output="$WORK/$stage.$name.bin"
  local compile_log="$WORK/$stage.$name.compile.log"
  local stdout="$WORK/$stage.$name.stdout"
  local stderr="$WORK/$stage.$name.stderr"
  local runner_log="$WORK/$stage.$name.runner.log"

  if ! compile_source "$stage" "$source" "$output" "$compile_log"; then
    echo "FAIL: $stage rejected positive FFI case $name" >&2
    tail -50 "$compile_log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 15 1024 \
    "$output" "$stderr" >"$stdout" 2>"$runner_log"; then
    echo "FAIL: $stage positive FFI executable failed: $name" >&2
    cat "$stderr" >&2
    cat "$runner_log" >&2
    return 1
  fi
  printf '%s' "$expected" >"$WORK/$name.expected.stdout"
  if ! cmp -s "$WORK/$name.expected.stdout" "$stdout" || [[ -s "$stderr" ]]; then
    echo "FAIL: $stage FFI output differs for $name" >&2
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
  expect_positive "$stage" valid "$FIXTURE_DIR/valid.cr" $'A\nB\nC\n'
  for name in missing_fixed missing_bare excess_fixed missing_variadic_prefix; do
    expect_rejection "$stage" "$name" 'wrong number of arguments'
  done
}
run_matrix original
[[ -z "$CANDIDATE" ]] || run_matrix candidate
echo 'PASS: original-first FFI fixed and variadic arity contract'
