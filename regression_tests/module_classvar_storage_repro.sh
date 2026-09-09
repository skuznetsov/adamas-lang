#!/bin/bash
set -euo pipefail

# The getter-only module fixture is the primary pre-fix regression: an old
# compiler emits an 8-byte pointer global which its getter reads as a 12-byte
# Nil|Bool union. The setter fixture is a candidate guard for the later runtime
# path (nil -> true -> cached true -> false -> cached false). A baseline host
# is optional; when supplied it is compiled from the same getter-only source.

ROOT=$(cd "$(dirname "$0")" && pwd)
RUN_SAFE=${RUN_SAFE:-$ROOT/../scripts/run_safe.sh}
CRYSTAL_PATH=${CRYSTAL_PATH:-}
CLANG=${CLANG:-clang}
PYTHON=${PYTHON:-python3}
CANDIDATE_COMPILER=${1:-${COMPILER:-$ROOT/../bin/adamas}}
BASELINE_COMPILER=${2:-${BASELINE_COMPILER:-}}
TMP_ROOT=${TMP_ROOT:-${TMPDIR:-/tmp}}
OUT=$(mktemp -d "$TMP_ROOT/adamas-module-classvar.XXXXXX")
cleanup() {
  if [ "${KEEP_OUT:-0}" != 1 ]; then
    rm -rf "$OUT"
  fi
}
trap cleanup EXIT

run_safe_expect() {
  local expected=$1
  local log=$2
  shift 2
  set +e
  "$@" >"$log" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -ne "$expected" ]; then
    echo "unexpected exit=$rc expected=$expected: $*" >&2
    cat "$log" >&2
    exit 1
  fi
}

run_safe_expect_asan_failure() {
  local log=$1
  shift
  set +e
  ASAN_OPTIONS=abort_on_error=1:detect_leaks=0 "$@" >"$log" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "baseline ASan run unexpectedly passed: $*" >&2
    cat "$log" >&2
    exit 1
  fi
  if ! rg -q 'ERROR: AddressSanitizer: global-buffer-overflow' "$log" || ! rg -q 'READ of size 12' "$log"; then
    echo "baseline nonzero run lacked an ASan diagnostic: $*" >&2
    cat "$log" >&2
    exit 1
  fi
}

compile_ir() {
  local compiler=$1
  local source=$2
  local output_base=$3
  local cache=$4
  local log=$5
  run_safe_expect 0 "$log" env CRYSTAL_PATH="$CRYSTAL_PATH" \
    CRYSTAL_CACHE_DIR="$cache" "$RUN_SAFE" "$compiler" 30 2048 \
    "$source" --no-prelude --emit llvm-ir -o "$output_base"
}

instrument_ir() {
  local input=$1
  local output=$2
  local log=$3
  run_safe_expect 0 "$log" "$RUN_SAFE" "$PYTHON" 30 512 \
    "$ROOT/instrument_asan_ir.py" "$input" "$output"
}

assert_one_global_shape() {
  local file=$1
  local pattern=$2
  local count
  count=$(rg -F -c -- "$pattern" "$file" || true)
  if [ "${count:-0}" -ne 1 ]; then
    echo "expected one global matching '$pattern' in $file, got ${count:-0}" >&2
    exit 1
  fi
}

assert_union_storage() {
  local file=$1
  local global_name=$2
  local union_store_count
  union_store_count=$(rg -F -c -- "store %Nil\$_\$OR\$_Bool.union" "$file" || true)
  [ "${union_store_count:-0}" -ge 1 ] || {
    echo "no union stores in $file" >&2
    exit 1
  }
  if rg -n "store ptr .*@${global_name}" "$file"; then
    echo "pointer-shaped store targets @${global_name} in $file" >&2
    exit 1
  fi
}

assert_no_sanitizer_diagnostic() {
  local log=$1
  if rg -qi 'AddressSanitizer|global-buffer-overflow' "$log"; then
    echo "candidate emitted a sanitizer diagnostic: $log" >&2
    cat "$log" >&2
    exit 1
  fi
}

run_candidate_case() {
  local label=$1
  local ll=$2
  local asan_ll="$OUT/$label-asan.ll"
  local binary="$OUT/$label"
  instrument_ir "$ll" "$asan_ll" "$OUT/$label-instrument.log"
  local definitions
  definitions=$(rg -c '^define .* sanitize_address \{' "$asan_ll" || true)
  [ "${definitions:-0}" -gt 0 ] || {
    echo "no sanitize_address definitions in $asan_ll" >&2
    exit 1
  }

  run_safe_expect 0 "$OUT/$label-link.log" "$RUN_SAFE" "$CLANG" 60 2048 \
    -O0 "$ll" -o "$binary"
  run_safe_expect 0 "$OUT/$label-run.log" "$RUN_SAFE" "$binary" 5 512
  run_safe_expect 0 "$OUT/$label-asan-link.log" "$RUN_SAFE" "$CLANG" 60 2048 \
    -O0 -g -fsanitize=address -fno-omit-frame-pointer "$asan_ll" -o "$binary-asan"
  run_safe_expect 0 "$OUT/$label-asan-run.log" env \
    ASAN_OPTIONS=abort_on_error=1:detect_leaks=0 "$RUN_SAFE" "$binary-asan" 5 1024
  assert_no_sanitizer_diagnostic "$OUT/$label-asan-run.log"
}

mkdir -p "$OUT/cache-primary-module" "$OUT/cache-primary-class" \
  "$OUT/cache-expanded-module" "$OUT/cache-expanded-class"

compile_ir "$CANDIDATE_COMPILER" "$ROOT/module_classvar_getter_repro.cr" "$OUT/primary-module" \
  "$OUT/cache-primary-module" "$OUT/primary-module-compiler.log"
compile_ir "$CANDIDATE_COMPILER" "$ROOT/class_classvar_getter_control.cr" "$OUT/primary-class" \
  "$OUT/cache-primary-class" "$OUT/primary-class-compiler.log"
compile_ir "$CANDIDATE_COMPILER" "$ROOT/module_classvar_cached_repro.cr" "$OUT/expanded-module" \
  "$OUT/cache-expanded-module" "$OUT/expanded-module-compiler.log"
compile_ir "$CANDIDATE_COMPILER" "$ROOT/class_classvar_cached_control.cr" "$OUT/expanded-class" \
  "$OUT/cache-expanded-class" "$OUT/expanded-class-compiler.log"

for ll in "$OUT/primary-module.ll" "$OUT/primary-class.ll" \
  "$OUT/expanded-module.ll" "$OUT/expanded-class.ll"; do
  [ -f "$ll" ] || { echo "compiler did not produce $ll" >&2; exit 1; }
done

assert_one_global_shape "$OUT/primary-module.ll" \
  '@NPModule__classvar__enabled = global %Nil$_$OR$_Bool.union zeroinitializer'
assert_one_global_shape "$OUT/primary-class.ll" \
  '@NPClass__classvar__enabled = global %Nil$_$OR$_Bool.union zeroinitializer'
assert_one_global_shape "$OUT/expanded-module.ll" \
  '@NPModule__classvar__enabled = global %Nil$_$OR$_Bool.union zeroinitializer'
assert_one_global_shape "$OUT/expanded-class.ll" \
  '@NPClass__classvar__enabled = global %Nil$_$OR$_Bool.union zeroinitializer'
assert_union_storage "$OUT/primary-module.ll" NPModule__classvar__enabled
assert_union_storage "$OUT/primary-class.ll" NPClass__classvar__enabled
assert_union_storage "$OUT/expanded-module.ll" NPModule__classvar__enabled
assert_union_storage "$OUT/expanded-class.ll" NPClass__classvar__enabled

run_candidate_case primary-module "$OUT/primary-module.ll"
run_candidate_case primary-class "$OUT/primary-class.ll"
run_candidate_case expanded-module "$OUT/expanded-module.ll"
run_candidate_case expanded-class "$OUT/expanded-class.ll"

if [ -n "$BASELINE_COMPILER" ]; then
  mkdir -p "$OUT/cache-baseline"
  compile_ir "$BASELINE_COMPILER" "$ROOT/module_classvar_getter_repro.cr" "$OUT/baseline-module" \
    "$OUT/cache-baseline" "$OUT/baseline-compiler.log"
  baseline_ll="$OUT/baseline-module.ll"
  [ -f "$baseline_ll" ] || { echo "baseline did not produce $baseline_ll" >&2; exit 1; }
  assert_one_global_shape "$baseline_ll" \
    '@NPModule__classvar__enabled = global ptr null'

  instrument_ir "$baseline_ll" "$OUT/baseline-asan.ll" "$OUT/baseline-instrument.log"
  run_safe_expect 0 "$OUT/baseline-link.log" "$RUN_SAFE" "$CLANG" 60 2048 \
    -O0 "$baseline_ll" -o "$OUT/baseline"
  run_safe_expect 0 "$OUT/baseline-run.log" "$RUN_SAFE" "$OUT/baseline" 5 512
  run_safe_expect 0 "$OUT/baseline-asan-link.log" "$RUN_SAFE" "$CLANG" 60 2048 \
    -O0 -g -fsanitize=address -fno-omit-frame-pointer "$OUT/baseline-asan.ll" \
    -o "$OUT/baseline-asan"
  run_safe_expect_asan_failure "$OUT/baseline-asan-run.log" env \
    ASAN_OPTIONS=abort_on_error=1:detect_leaks=0 "$RUN_SAFE" \
    "$OUT/baseline-asan" 5 1024
  echo "baseline getter-only: pointer global=1, ASan READ12=1"
fi

echo "candidate getter-only module/class: ASan=0"
echo "candidate nil/true/cached/false module/class guard: ASan=0"
echo "artifacts: $OUT"
