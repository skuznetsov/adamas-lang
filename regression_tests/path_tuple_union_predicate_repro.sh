#!/usr/bin/env bash
# Compare original Crystal and an Adamas candidate on valid public Path controls.
# The candidate ASan run is a hard gate: current pre-fix hosts fail it; a fixed
# candidate must exit 0 and match the normal expected stdout.
set -u -o pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd -- "$script_dir/.." && pwd)"
run_safe="$repo/scripts/run_safe.sh"
crystal_src="${CRYSTAL_PATH:?Set CRYSTAL_PATH to the external Crystal stdlib}"
original_compiler="${CRYSTAL:-crystal}"
fixture="$script_dir/path_tuple_union_predicate_repro.cr"
expected="$script_dir/path_tuple_union_predicate_repro.expected"
candidate="${1:?usage: $0 CANDIDATE_COMPILER [OUTPUT_DIR]}"
out="${2:-$(mktemp -d "${TMPDIR:-/tmp}/path-tuple-union.XXXXXX")}"
mkdir -p "$out"

run_status() {
  local name="$1"
  shift
  local log="$out/$name.log"
  local rc
  if "$@" >"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  printf '%s\n' "$rc" >"$out/$name.rc"
  printf '%s rc=%s log=%s\n' "$name" "$rc" "$log"
}

status() {
  cat "$out/$1.rc"
}

extract_stdout() {
  awk '/^=== STDOUT ===$/ {inside=1; next} /^=== STDERR ===$/ {inside=0} inside {print}' "$1"
}

fail_with_log() {
  printf 'FAIL: %s\n' "$1" >&2
  return 1
}

mkdir -p "$out/original-cache" "$out/candidate-cache"

run_status original-build env \
  CRYSTAL_PATH="$crystal_src" \
  CRYSTAL_CACHE_DIR="$out/original-cache" \
  "$run_safe" "$original_compiler" 300 8192 build \
  "$fixture" -o "$out/original"
[[ "$(status original-build)" == 0 ]] || fail_with_log "original build" || exit 1

run_status original-run "$run_safe" "$out/original" 10 1024
[[ "$(status original-run)" == 0 ]] || fail_with_log "original run" || exit 1
extract_stdout "$out/original-run.log" >"$out/original.stdout"
diff -u "$expected" "$out/original.stdout" >"$out/original.diff" || {
  cat "$out/original.diff" >&2
  fail_with_log "original stdout differs from expected" || exit 1
}

run_status candidate-emit env \
  CRYSTAL_PATH="$crystal_src" \
  CRYSTAL_CACHE_DIR="$out/candidate-cache" \
  "$run_safe" "$candidate" 300 8192 \
  "$fixture" --emit llvm-ir -o "$out/candidate"
[[ "$(status candidate-emit)" == 0 ]] || fail_with_log "candidate LLVM emission" || exit 1

link_flags=(
  -lgc -lpcre2-8 -lpcre
  -L/opt/homebrew/opt/bdw-gc/lib
  -L/opt/homebrew/opt/pcre2/lib
  -L/opt/homebrew/opt/pcre/lib
  -liconv
  -Wl,-stack_size,0x4000000
)
clang_bin="${CLANG:-/opt/homebrew/opt/llvm/bin/clang}"

run_status candidate-link "$run_safe" "$clang_bin" 180 8192 -O0 \
  "$out/candidate.ll" "${link_flags[@]}" -o "$out/candidate"
[[ "$(status candidate-link)" == 0 ]] || fail_with_log "candidate normal link" || exit 1

run_status candidate-run "$run_safe" "$out/candidate" 10 1024
[[ "$(status candidate-run)" == 0 ]] || fail_with_log "candidate normal run" || exit 1
extract_stdout "$out/candidate-run.log" >"$out/candidate.stdout"
diff -u "$expected" "$out/candidate.stdout" >"$out/candidate.diff" || {
  cat "$out/candidate.diff" >&2
  fail_with_log "candidate normal stdout differs from expected" || exit 1
}

python3 - "$out/candidate.ll" "$out/candidate.asan.ll" >"$out/asan-instrument.log" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
instrumented, count = re.subn(r'^(define .*?)\s*\{', r'\1 sanitize_address {', source, flags=re.M)
if not count:
    raise SystemExit("No LLVM function definitions were instrumented")
Path(sys.argv[2]).write_text(instrumented)
print(f"instrumented_defines={count}")
PY
if [[ ! -s "$out/candidate.asan.ll" ]]; then
  fail_with_log "ASan LLVM emission" || exit 1
fi

run_status candidate-asan-link "$run_safe" "$clang_bin" 180 8192 -O0 -fsanitize=address \
  "$out/candidate.asan.ll" "${link_flags[@]}" -o "$out/candidate.asan"
[[ "$(status candidate-asan-link)" == 0 ]] || fail_with_log "candidate ASan link" || exit 1

run_status candidate-asan-run env ASAN_OPTIONS=detect_leaks=0 \
  "$run_safe" "$out/candidate.asan" 10 2048
asan_rc="$(status candidate-asan-run)"
if [[ "$asan_rc" != 0 ]]; then
  cat "$out/candidate-asan-run.log" >&2
  fail_with_log "candidate ASan run exited $asan_rc" || exit 1
fi
extract_stdout "$out/candidate-asan-run.log" >"$out/candidate-asan.stdout"
diff -u "$expected" "$out/candidate-asan.stdout" >"$out/candidate-asan.diff" || {
  cat "$out/candidate-asan.diff" >&2
  fail_with_log "candidate ASan stdout differs from expected" || exit 1
}

printf 'PASS: original, candidate normal, and candidate ASan Path controls\n'
printf 'OUTPUT_DIR=%s\n' "$out"
