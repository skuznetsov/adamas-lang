#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
fixtures="$root/regression_tests/fixtures/union_hierarchy_dispatch"
work="$(mktemp -d "${TMPDIR:-/tmp}/union-hierarchy-dispatch.XXXXXX")"
cleanup() {
  if [[ "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'artifacts retained %s\n' "$work" >&2
  else
    rm -rf -- "$work"
  fi
}
trap cleanup EXIT
export RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

check_compiler() {
  local label="$1" compiler="$2"
  shift 2
  local name expected output rc
  while read -r name expected; do
    output="$work/$label-$name"
    rc=0
    "$safe" "$compiler" 90 8192 build "$fixtures/$name.cr" \
      "$@" --no-debug -o "$output" </dev/null >"$output.compile.log" 2>&1 || rc=$?
    if [[ "$expected" == reject ]]; then
      if [[ "$rc" -ne 1 || -e "$output" ]] ||
          ! rg -qi 'undefined method|no overload matches' "$output.compile.log"; then
        cat "$output.compile.log" >&2
        echo "$label $name expected a method admission diagnostic" >&2
        return 1
      fi
      continue
    fi
    if [[ "$rc" -ne 0 ]]; then
      cat "$output.compile.log" >&2
      return 1
    fi
    if ! "$safe" "$output" 5 512 </dev/null >"$output.stdout" 2>"$output.stderr" ||
        ! printf '%s\n' "$expected" | cmp -s - "$output.stdout"; then
      cat "$output.stdout" "$output.stderr" >&2
      echo "$label $name output mismatch" >&2
      return 1
    fi
  done <<'CASES'
positive ABCCBADEFDEFDC
bare_only ABC
numeric_name AB
tagged AABB
missing_method reject
CASES
}

check_compiler original "$original" --prelude=empty
check_compiler candidate "$candidate" --no-prelude --no-ast-cache --no-llvm-cache
echo 'union_hierarchy_dispatch_repro PASS'
