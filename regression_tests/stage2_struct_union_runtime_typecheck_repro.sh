#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

compiler="$1"
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workdir="$(mktemp -d "${TMPDIR:-/tmp}/stage2_struct_union_runtime_typecheck.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

src="$workdir/repro.cr"
out_bin="$workdir/repro_bin"
compile_stdout="$workdir/compile_stdout.txt"
compile_stderr="$workdir/compile_stderr.txt"
run_log="$workdir/run.log"
stdout_only="$workdir/stdout.txt"

cat >"$src" <<'CR'
require "set"

set = Set(String).new
set << "a"
value = (1 == 1) ? set : "b"
puts value.is_a?(Set(String))
puts value.is_a?(String)
puts value.as(Set(String)).includes?("a")
puts value.object_id == set.object_id
CR

set +e
"$compiler" "$src" -o "$out_bin" >"$compile_stdout" 2>"$compile_stderr"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "inconclusive: compile failed with status=$compile_status" >&2
  echo "--- compiler stdout ---" >&2
  cat "$compile_stdout" >&2
  echo "--- compiler stderr ---" >&2
  cat "$compile_stderr" >&2
  exit 2
fi

set +e
"$repo_root/scripts/run_safe.sh" "$out_bin" 5 512 >"$run_log" 2>&1
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  if rg -q '\[CRASH\] Segfault|\[CRASH\] Abort' "$run_log"; then
    echo "reproduced: struct-containing union still crashes or mis-tags at runtime"
    exit 1
  fi
  echo "inconclusive: runtime failed with status=$run_status" >&2
  echo "--- run log ---" >&2
  cat "$run_log" >&2
  exit 2
fi

awk '/^=== STDOUT ===$/ { capture = 1; next } /^=== STDERR ===$/ { capture = 0 } capture { print }' "$run_log" >"$stdout_only"

cat >"$workdir/expected.txt" <<'EOF'
true
false
true
true
EOF

if cmp -s "$stdout_only" "$workdir/expected.txt"; then
  echo "not reproduced"
  exit 0
fi

echo "reproduced: struct-containing union still misclassifies runtime type checks"
echo "--- run log ---" >&2
cat "$run_log" >&2
exit 1
