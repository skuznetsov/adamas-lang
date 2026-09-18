#!/usr/bin/env bash
# External-prelude regression for a homogeneous union of one- and two-element
# tuples.  The tuple cases cover a captured accumulator, next, break, a
# conditional nonlocal return, and an unconditional nonlocal return.  The
# Path cases exercise the same tuple iteration through Path.posix/windows
# separators and joins; the POSIX one-element separator tuple is the short
# allocation that exposed the old out-of-bounds second load under ASan.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_safe="$root/scripts/run_safe.sh"
source="$root/regression_tests/tuple_union_iteration_repro.cr"
candidate="${1:-$root/bin/adamas}"
baseline="${2:-${BASELINE_COMPILER:-}}"
original="${ORIGINAL_CRYSTAL:-/Users/sergey/Projects/Crystal/crystal/bin/crystal}"
stdlib="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
cache="${CRYSTAL_CACHE_DIR:-/private/tmp/adamas-tuple-cache}"
python="${PYTHON:-python3}"
clang="${CLANG:-clang}"

if [[ ! -x "$original" ]]; then
  original="$(command -v crystal || true)"
fi
if [[ ! -x "$candidate" ]]; then
  echo "ERROR: candidate compiler not found: $candidate" >&2
  exit 2
fi
if [[ -z "$original" || ! -x "$original" ]]; then
  echo "ERROR: original Crystal compiler not found" >&2
  exit 2
fi
if [[ ! -x "$run_safe" ]]; then
  echo "ERROR: run_safe.sh not found: $run_safe" >&2
  exit 2
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-tuple-union.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_work=$work"
  else
    rm -rf "$work"
  fi
}
trap cleanup EXIT
mkdir -p "$cache"

extract_stdout() {
  local input="$1"
  local output="$2"
  awk '
    /^=== STDOUT ===$/ { in_stdout = 1; next }
    /^=== STDERR ===$/ { in_stdout = 0 }
    in_stdout { print }
  ' "$input" >"$output"
}

run_expect_zero() {
  local log="$1"
  shift
  local rc=0
  "$@" >"$log" 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL: command exited $rc: $*" >&2
    tail -80 "$log" >&2 || true
    return 1
  fi
}

run_allow_failure() {
  local log="$1"
  shift
  local rc=0
  "$@" >"$log" 2>&1 || rc=$?
  printf '%s\n' "$rc"
}

compare_stdout() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if ! diff -u "$expected" "$actual" >"$work/$label.stdout.diff"; then
    echo "FAIL: $label output differs from the original Crystal oracle" >&2
    cat "$work/$label.stdout.diff" >&2
    return 1
  fi
}

original_bin="$work/original.bin"
original_build_log="$work/original-build.log"
original_run_log="$work/original-run.log"
original_stdout="$work/original.stdout"

# The external source tree is intentional: the fixture must use the real Path
# implementation rather than a no-prelude custom Tuple stand-in.  Apple ld is
# selected by default because Homebrew lld can reject the current SDK TAPI;
# ORIGINAL_LINK_FLAGS may override it with one string.
original_link_flags="${ORIGINAL_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
run_expect_zero "$original_build_log" env \
  CRYSTAL_PATH="$stdlib" CRYSTAL_CACHE_DIR="$cache" \
  "$run_safe" "$original" 120 8192 build "$source" \
  "--link-flags=$original_link_flags" -o "$original_bin"
run_expect_zero "$original_run_log" "$run_safe" "$original_bin" 10 1024
extract_stdout "$original_run_log" "$original_stdout"

candidate_bin="$work/candidate.bin"
candidate_build_log="$work/candidate-build.log"
candidate_run_log="$work/candidate-run.log"
candidate_stdout="$work/candidate.stdout"
candidate_link_flags="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
run_expect_zero "$candidate_build_log" env \
  CRYSTAL_PATH="$stdlib" CRYSTAL_CACHE_DIR="$cache" \
  ADAMAS_EXTRA_LINK_FLAGS="$candidate_link_flags" \
  "$run_safe" "$candidate" 180 8192 "$source" -o "$candidate_bin"
run_expect_zero "$candidate_run_log" "$run_safe" "$candidate_bin" 10 1024
extract_stdout "$candidate_run_log" "$candidate_stdout"
compare_stdout "$original_stdout" "$candidate_stdout" candidate

candidate_ll="$candidate_bin.ll"
if [[ ! -s "$candidate_ll" ]]; then
  echo "FAIL: candidate did not preserve LLVM IR at $candidate_ll" >&2
  exit 1
fi

instrument="$root/regression_tests/instrument_asan_ir.py"
candidate_asan_ll="$work/candidate-asan.ll"
candidate_asan_bin="$work/candidate-asan.bin"
run_expect_zero "$work/candidate-instrument.log" "$run_safe" "$python" 30 512 \
  "$instrument" "$candidate_ll" "$candidate_asan_ll"
if ! rg -q '^define .* sanitize_address \{' "$candidate_asan_ll"; then
  echo "FAIL: ASan instrumentation added no sanitize_address definitions" >&2
  exit 1
fi

asan_link_flags=(-O0 -g -fsanitize=address -fno-omit-frame-pointer \
  -fuse-ld=/usr/bin/ld "$candidate_asan_ll" -lgc -lpcre2-8 -lpcre)
if [[ "$(uname -s)" == "Darwin" ]]; then
  if [[ -z "${CLANG:-}" && -x /opt/homebrew/opt/llvm/bin/clang ]]; then
    clang=/opt/homebrew/opt/llvm/bin/clang
  fi
  asan_link_flags+=(
    -L/opt/homebrew/opt/bdw-gc/lib
    -L/opt/homebrew/opt/pcre2/lib
    -L/opt/homebrew/opt/pcre/lib
    -liconv
    -Wl,-stack_size,0x4000000
  )
fi
asan_link_flags+=(-o "$candidate_asan_bin")
run_expect_zero "$work/candidate-asan-link.log" "$run_safe" "$clang" 90 8192 \
  "${asan_link_flags[@]}"
candidate_asan_run_log="$work/candidate-asan-run.log"
run_expect_zero "$candidate_asan_run_log" env \
  ASAN_OPTIONS=abort_on_error=1:detect_leaks=0 \
  "$run_safe" "$candidate_asan_bin" 10 1024
if rg -qi 'AddressSanitizer|heap-buffer-overflow|global-buffer-overflow|stack-buffer-overflow' \
  "$candidate_asan_run_log"; then
  echo "FAIL: candidate ASan run reported a sanitizer diagnostic" >&2
  cat "$candidate_asan_run_log" >&2
  exit 1
fi
extract_stdout "$candidate_asan_run_log" "$work/candidate-asan.stdout"
compare_stdout "$original_stdout" "$work/candidate-asan.stdout" candidate-asan

if [[ -n "$baseline" ]]; then
  if [[ ! -x "$baseline" ]]; then
    echo "FAIL: baseline compiler is not executable: $baseline" >&2
    exit 2
  fi

  baseline_bin="$work/baseline.bin"
  run_expect_zero "$work/baseline-build.log" env \
    CRYSTAL_PATH="$stdlib" CRYSTAL_CACHE_DIR="$cache" \
    ADAMAS_EXTRA_LINK_FLAGS="$candidate_link_flags" \
    "$run_safe" "$baseline" 180 8192 "$source" -o "$baseline_bin"
  if [[ ! -s "$baseline_bin.ll" ]]; then
    echo "FAIL: baseline did not preserve LLVM IR at $baseline_bin.ll" >&2
    exit 1
  fi

  # The old baseline is expected to fail this normal run; its ASan result below
  # is the required negative control for the candidate's clean ASan run.
  run_allow_failure "$work/baseline-run.log" "$run_safe" "$baseline_bin" 10 1024 >/dev/null

  baseline_asan_ll="$work/baseline-asan.ll"
  run_expect_zero "$work/baseline-instrument.log" "$run_safe" "$python" 30 512 \
    "$instrument" "$baseline_bin.ll" "$baseline_asan_ll"
  if ! rg -q '^define .* sanitize_address \{' "$baseline_asan_ll"; then
    echo "FAIL: baseline ASan instrumentation added no sanitize_address definitions" >&2
    exit 1
  fi

  baseline_asan_link_flags=(-O0 -g -fsanitize=address -fno-omit-frame-pointer \
    -fuse-ld=/usr/bin/ld "$baseline_asan_ll" -lgc -lpcre2-8 -lpcre)
  if [[ "$(uname -s)" == "Darwin" ]]; then
    baseline_asan_link_flags+=(
      -L/opt/homebrew/opt/bdw-gc/lib
      -L/opt/homebrew/opt/pcre2/lib
      -L/opt/homebrew/opt/pcre/lib
      -liconv
      -Wl,-stack_size,0x4000000
    )
  fi
  baseline_asan_link_flags+=(-o "$work/baseline-asan.bin")
  run_expect_zero "$work/baseline-asan-link.log" "$run_safe" "$clang" 90 8192 \
    "${baseline_asan_link_flags[@]}"

  baseline_asan_run_log="$work/baseline-asan-run.log"
  baseline_asan_run_rc="$(run_allow_failure "$baseline_asan_run_log" env \
    ASAN_OPTIONS=abort_on_error=1:detect_leaks=0 \
    "$run_safe" "$work/baseline-asan.bin" 10 1024)"
  if [[ "$baseline_asan_run_rc" -eq 0 ]] ||
     ! rg -q 'AddressSanitizer: heap-buffer-overflow' "$baseline_asan_run_log" ||
     ! rg -q 'READ of size 4' "$baseline_asan_run_log" ||
     ! rg -q 'in sum_each' "$baseline_asan_run_log"; then
    echo "FAIL: baseline ASan did not reproduce heap-buffer-overflow READ4 in sum_each" >&2
    tail -80 "$baseline_asan_run_log" >&2 || true
    exit 1
  fi
  echo "baseline ASan: expected heap-buffer-overflow READ4 in sum_each"
fi

echo "PASS: external-prelude tuple union iteration, Path controls, candidate normal and ASan"
