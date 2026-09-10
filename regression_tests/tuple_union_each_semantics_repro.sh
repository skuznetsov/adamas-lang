#!/usr/bin/env bash
# Compare tuple iteration, callback control flow, and return values with Crystal.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd -- "$script_dir/.." && pwd)"
candidate="${1:?usage: $0 CANDIDATE_COMPILER [OUTPUT_DIR]}"
out="${2:-$(mktemp -d "${TMPDIR:-/tmp}/tuple-union-semantics.XXXXXX")}"
fixture="$script_dir/tuple_union_each_semantics_repro.cr"
expected="$script_dir/tuple_union_each_semantics_repro.expected"
run_safe="$repo/scripts/run_safe.sh"
: "${CRYSTAL_PATH:?Set CRYSTAL_PATH to the external Crystal stdlib}"
mkdir -p "$out"
export CRYSTAL_CACHE_DIR="$out/cache"
mkdir -p "$CRYSTAL_CACHE_DIR"

extract_stdout() {
  awk '/^=== STDOUT ===$/ {inside=1; next} /^=== STDERR ===$/ {inside=0} inside {print}' "$1"
}

"$run_safe" "${CRYSTAL:-crystal}" 180 8192 build "$fixture" \
  -o "$out/original" >"$out/original-build.log" 2>&1
"$run_safe" "$out/original" 10 1024 >"$out/original-run.log" 2>&1
extract_stdout "$out/original-run.log" >"$out/original.stdout"
diff -u "$expected" "$out/original.stdout"

"$run_safe" "$candidate" 180 8192 "$fixture" \
  -o "$out/candidate" >"$out/candidate-build.log" 2>&1
"$run_safe" "$out/candidate" 10 2048 >"$out/candidate-run.log" 2>&1
extract_stdout "$out/candidate-run.log" >"$out/candidate.stdout"
diff -u "$expected" "$out/candidate.stdout"

printf 'PASS: original and candidate tuple iteration semantics\n'
printf 'OUTPUT_DIR=%s\n' "$out"
