#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SAFE_RUNNER="$REPO_ROOT/scripts/run_safe.sh"

if [ "$#" -gt 1 ]; then
  echo "usage: $0 [candidate_compiler]" >&2
  exit 2
fi

ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}"
CANDIDATE_COMPILER="${1:-$REPO_ROOT/bin/adamas}"
CLANG_BIN="${CLANG_BIN:-$(command -v clang || true)}"

if [ ! -x "$SAFE_RUNNER" ]; then
  echo "missing safe runner: $SAFE_RUNNER" >&2
  exit 2
fi
if [ ! -x "$ORIGINAL_CRYSTAL" ]; then
  echo "missing original Crystal compiler: $ORIGINAL_CRYSTAL" >&2
  exit 2
fi
if [ ! -x "$CANDIDATE_COMPILER" ]; then
  echo "missing candidate compiler: $CANDIDATE_COMPILER" >&2
  exit 2
fi
if [ -z "$CLANG_BIN" ] || [ ! -x "$CLANG_BIN" ]; then
  echo "clang is required to build the variadic C helper" >&2
  exit 2
fi

if [ -z "${CRYSTAL_PATH:-}" ]; then
  CRYSTAL_PATH="$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" 10 1024 env CRYSTAL_PATH)"
fi
export CRYSTAL_PATH
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/c-varargs-source-abi.XXXXXX")"
EVIDENCE_LOG="${VARARGS_EVIDENCE_LOG:-$WORK_DIR/summary.log}"
SUMMARY_TMP="${EVIDENCE_LOG}.tmp.$$"
cleanup() {
  if [ -f "$SUMMARY_TMP" ]; then
    mv "$SUMMARY_TMP" "$EVIDENCE_LOG"
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

SOURCE="$WORK_DIR/probe.cr"
HELPER_SOURCE="$WORK_DIR/helper.c"
HELPER_OBJECT="$WORK_DIR/helper.o"
ORIGINAL_BIN="$WORK_DIR/original.bin"
CANDIDATE_BIN="$WORK_DIR/candidate.bin"

cat >"$HELPER_SOURCE" <<'C'
#include <fcntl.h>
#include <errno.h>
#include <semaphore.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int failed_cases;
static char sem_name[64];

static int report_case(const char *name, int passed) {
  int status = passed ? 0 : 1;
  printf("%s status=%d\n", name, status);
  fflush(stdout);
  if (status != 0) ++failed_cases;
  return status;
}

void adamas_finish(void) {
  exit(failed_cases == 0 ? 0 : 1);
}

int adamas_user_integer_tail(int fixed, ...) {
  va_list args;
  va_start(args, fixed);
  int first = va_arg(args, int);
  int second = va_arg(args, int);
  int third = va_arg(args, int);
  va_end(args);
  return report_case("integer_tail", fixed == 41 && first == 7 && second == -11 && third == 2048);
}

int adamas_user_register_boundary(int fixed, int count, ...) {
  static const int expected[] = {101, 102, 103, 104, 105, 106, 107, 108, 109};
  va_list args;
  va_start(args, count);
  int passed = fixed == 3 && count == (int)(sizeof(expected) / sizeof(expected[0]));
  for (int i = 0; i < (int)(sizeof(expected) / sizeof(expected[0])); ++i) {
    int actual = va_arg(args, int);
    if (actual != expected[i]) passed = 0;
  }
  va_end(args);
  return report_case("register_boundary", passed);
}

int adamas_user_mixed_promotions(float fixed_float, int fixed_int, ...) {
  va_list args;
  va_start(args, fixed_int);
  double promoted_float = va_arg(args, double);
  int promoted_int8 = va_arg(args, int);
  int promoted_uint8 = va_arg(args, int);
  int promoted_int16 = va_arg(args, int);
  int promoted_uint16 = va_arg(args, int);
  va_end(args);
  int passed = fixed_int == 23 && fixed_float == 1.5f && promoted_float == 2.25 &&
               promoted_int8 == -7 && promoted_uint8 == 250 && promoted_int16 == -123 &&
               promoted_uint16 == 65530;
  return report_case("mixed_promotions", passed);
}

int adamas_user_proc_prefix(int (*callback)(int), int fixed, ...) {
  va_list args;
  va_start(args, fixed);
  int tail = va_arg(args, int);
  va_end(args);
  int callback_result = callback ? callback(fixed) : -1;
  return report_case("proc_prefix_callback", callback_result == 20 && tail == 73);
}

static int adamas_proc_prefix_identity(int value) {
  return value;
}

void *adamas_proc_prefix_callback_address(void) {
  return (void *)adamas_proc_prefix_identity;
}

void *adamas_proc_prefix_callback_context(void) {
  return NULL;
}

void adamas_user_void_tail(int fixed, ...) {
  va_list args;
  va_start(args, fixed);
  int first = va_arg(args, int);
  int second = va_arg(args, int);
  va_end(args);
  report_case("void_return", fixed == 37 && first == 5 && second == 9);
}

int adamas_user_no_vararg_tail(int fixed, ...) {
  return report_case("no_vararg_tail", fixed == 91);
}

int adamas_fixed_control(int fixed, int tail) {
  return report_case("fixed_control", fixed == 12 && tail == 34);
}

const char *adamas_varargs_sem_name(void) {
  snprintf(sem_name, sizeof(sem_name), "/adamas-varargs-contract-%ld", (long)getpid());
  sem_unlink(sem_name);
  return sem_name;
}

int adamas_varargs_sem_flags(void) {
  return O_CREAT | O_EXCL;
}

int adamas_check_sem(void *opaque_sem) {
  sem_t *sem = (sem_t *)opaque_sem;
  int passed = sem != SEM_FAILED;
  if (passed) {
    int first_wait = sem_trywait(sem);
    int second_wait = sem_trywait(sem);
    passed = first_wait == 0 && second_wait == -1 && errno == EAGAIN;
  }
  if (sem != SEM_FAILED) sem_close(sem);
  sem_unlink(sem_name);
  return report_case("sem_open_alias", passed);
}
C

cat >"$SOURCE" <<'CR'
require "primitives"
require "proc"

@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib C
  fun adamas_user_integer_tail(fixed : Int32, ...) : Int32
  fun adamas_user_register_boundary(fixed : Int32, count : Int32, ...) : Int32
  fun adamas_user_mixed_promotions(fixed_float : Float32, fixed_int : Int32, ...) : Int32
  fun adamas_user_proc_prefix(callback : (Int32 -> Int32), fixed : Int32, ...) : Int32
  fun adamas_proc_prefix_callback_address : Void*
  fun adamas_proc_prefix_callback_context : Void*
  fun exit(status : Int32) : NoReturn
  fun adamas_user_void_tail(fixed : Int32, ...) : Void
  fun adamas_user_no_vararg_tail(fixed : Int32, ...) : Int32
  fun adamas_fixed_control(fixed : Int32, tail : Int32) : Int32
  fun adamas_varargs_sem_name : UInt8*
  fun adamas_varargs_sem_flags : Int32
  fun sem_open_alias = sem_open(name : UInt8*, flags : Int32, ...) : Void*
  fun adamas_check_sem(sem : Void*) : Int32
  fun adamas_finish : Void
end

# The original no-prelude compiler emits a closure-conversion guard at a C
# callback boundary. A valid null-context Proc must not reach this sentinel.
def raise(message : String) : NoReturn
  C.exit(93)
end

C.adamas_user_integer_tail(41, 7, -11, 2048)
C.adamas_user_register_boundary(3, 9, 101, 102, 103, 104, 105, 106, 107, 108, 109)
C.adamas_user_mixed_promotions(1.5_f32, 23, 2.25_f32, -7_i8, 250_u8, -123_i16, 65530_u16)
callback = Proc(Int32, Int32).new(C.adamas_proc_prefix_callback_address, C.adamas_proc_prefix_callback_context)
C.adamas_user_proc_prefix(callback, 20, 73)
C.adamas_user_void_tail(37, 5, 9)
C.adamas_user_no_vararg_tail(91)
C.adamas_fixed_control(12, 34)
sem = C.sem_open_alias(C.adamas_varargs_sem_name, C.adamas_varargs_sem_flags, 0o600, 1_u32)
C.adamas_check_sem(sem)
C.adamas_finish
CR

mkdir -p "$(dirname -- "$EVIDENCE_LOG")"
{
  printf 'candidate=%s\n' "$CANDIDATE_COMPILER"
  printf 'original_crystal=%s\n' "$ORIGINAL_CRYSTAL"
  printf 'clang=%s\n' "$CLANG_BIN"
  printf 'stdlib_source=%s\n' "$CRYSTAL_PATH"
  printf 'stdlib_library=%s\n' "${CRYSTAL_LIBRARY_PATH:-<compiler default>}"
  printf 'compile_safe_runner=120s/4096MiB; run_safe_runner=8s/512MiB\n'
  printf 'original_helper_linking=--link-flags=<helper.o>\n'
  printf 'candidate_helper_linking=ADAMAS_EXTRA_LINK_FLAGS (no CLI --link-flags option)\n'
} >"$SUMMARY_TMP"

if ! "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" 10 512 --version >"$WORK_DIR/original-version.log" 2>&1; then
  printf 'original_version_status=failed\n' | tee -a "$SUMMARY_TMP" >&2
  sed -n '1,40p' "$WORK_DIR/original-version.log" | tee -a "$SUMMARY_TMP" >&2
  exit 1
fi
printf 'original_version=' >>"$SUMMARY_TMP"
awk '/^=== STDOUT ===/{capture=1;next}/^=== STDERR ===/{capture=0}capture' "$WORK_DIR/original-version.log" | tr -d '\r' | tr '\n' ' ' >>"$SUMMARY_TMP"
printf '\n' >>"$SUMMARY_TMP"

echo "Building the shared C va_arg helper with $CLANG_BIN"
if ! "$SAFE_RUNNER" "$CLANG_BIN" 120 4096 -std=c11 -Wall -Wextra -Werror -O0 -c "$HELPER_SOURCE" -o "$HELPER_OBJECT" >"$WORK_DIR/clang.log" 2>&1; then
  echo "clang failed; see $WORK_DIR/clang.log" >&2
  printf 'clang_status=failed\n' | tee -a "$SUMMARY_TMP" >&2
  sed -n '1,100p' "$WORK_DIR/clang.log" | tee -a "$SUMMARY_TMP" >&2
  exit 1
fi
printf 'clang_build_status=0\n' | tee -a "$SUMMARY_TMP"

EXPECTED_CASES=(integer_tail register_boundary mixed_promotions proc_prefix_callback void_return no_vararg_tail fixed_control sem_open_alias)

compile_and_run() {
  local label="$1"
  local compiler="$2"
  local output_bin="$3"
  local build_log="$WORK_DIR/$label.build.log"
  local run_log="$WORK_DIR/$label.run.log"
  local build_status=0
  local run_status=0
  local case_name
  local expected_line
  local case_count
  local stdout_file="$WORK_DIR/$label.stdout"

  echo "Compiling with $label: $compiler"
  set +e
  if [ "$label" = original ]; then
    CRYSTAL_CACHE_DIR="$WORK_DIR/$label-cache" "$SAFE_RUNNER" "$compiler" 180 8192 \
      build "$SOURCE" --prelude=empty -o "$output_bin" "--link-flags=$HELPER_OBJECT" >"$build_log" 2>&1
    build_status=$?
  else
    CRYSTAL_CACHE_DIR="$WORK_DIR/$label-cache" ADAMAS_EXTRA_LINK_FLAGS="$HELPER_OBJECT" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$SOURCE" --prelude=empty -o "$output_bin" >"$build_log" 2>&1
    build_status=$?
  fi
  set -e
  printf '%s_build_status=%s\n' "$label" "$build_status" | tee -a "$SUMMARY_TMP"
  if [ "$build_status" -ne 0 ]; then
    sed -n '1,120p' "$build_log" | tee -a "$SUMMARY_TMP" >&2
    return 1
  fi

  set +e
  "$SAFE_RUNNER" "$output_bin" 8 512 >"$run_log" 2>&1
  run_status=$?
  set -e
  printf '%s_run_status=%s\n' "$label" "$run_status" | tee -a "$SUMMARY_TMP"
  awk '/^=== STDOUT ===/{capture=1;next}/^=== STDERR ===/{capture=0}capture' "$run_log" | tr -d '\r' >"$stdout_file"
  cat "$stdout_file" | tee -a "$SUMMARY_TMP"

  local failed=0
  for case_name in "${EXPECTED_CASES[@]}"; do
    expected_line="$case_name status=0"
    if ! grep -Fxq "$expected_line" "$stdout_file"; then
      printf '%s missing expected case line: %s\n' "$label" "$expected_line" | tee -a "$SUMMARY_TMP" >&2
      failed=1
    fi
  done
  case_count="$(grep -Ec '^[a-z_]+ status=[0-9]+$' "$stdout_file" || true)"
  if [ "$case_count" -ne "${#EXPECTED_CASES[@]}" ]; then
    printf '%s expected %s case results, observed %s\n' "$label" "${#EXPECTED_CASES[@]}" "$case_count" | tee -a "$SUMMARY_TMP" >&2
    failed=1
  fi
  if [ "$run_status" -ne 0 ]; then
    printf '%s test binary exited with status %s\n' "$label" "$run_status" | tee -a "$SUMMARY_TMP" >&2
    failed=1
  fi
  return "$failed"
}

overall_status=0
compile_and_run original "$ORIGINAL_CRYSTAL" "$ORIGINAL_BIN" || overall_status=1
if [ "$overall_status" -eq 0 ]; then
  compile_and_run candidate "$CANDIDATE_COMPILER" "$CANDIDATE_BIN" || overall_status=1
else
  printf 'candidate_skipped=original_qualification_failed\n' | tee -a "$SUMMARY_TMP"
fi

if [ "$overall_status" -eq 0 ]; then
  printf 'result=PASS\n' | tee -a "$SUMMARY_TMP"
else
  printf 'result=FAIL\n' | tee -a "$SUMMARY_TMP"
fi
mv "$SUMMARY_TMP" "$EVIDENCE_LOG"
if [ -n "${VARARGS_EVIDENCE_LOG:-}" ]; then
  echo "summary: $EVIDENCE_LOG"
fi
exit "$overall_status"
