#!/usr/bin/env bash
# Keep a static typeof union type object distinct from a runtime class union.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
FIXTURES="$ROOT/regression_tests/static_union_type_object"

if [[ ! -x "$SAFE" || ! -x "$ORIGINAL" || ! -d "$FIXTURES" ]]; then
  echo "ERROR: safe runner, stock Crystal, and fixtures are required" >&2
  exit 2
fi
if [[ "${ORIGINAL_ONLY:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  echo "ERROR: candidate compiler is not executable: $CANDIDATE" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/static-union-type-object.XXXXXX")"
trap 'status=$?; if [[ "$status" -eq 0 && "${KEEP_ARTIFACTS:-0}" != 1 ]]; then rm -rf -- "$WORK"; else printf "kept_artifacts=%s\n" "$WORK" >&2; fi' EXIT
export ADAMAS_LLVM_CACHE=0
export CRYSTAL_CACHE_DIR="$WORK/cache"
mkdir -p "$CRYSTAL_CACHE_DIR"
if [[ "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--L/opt/homebrew/lib -lgc -fuse-ld=/usr/bin/ld}"
  export ORIGINAL_CRYSTAL_LINK_FLAGS="${ORIGINAL_CRYSTAL_LINK_FLAGS:--L/opt/homebrew/lib -lgc -fuse-ld=/usr/bin/ld}"
fi

compile() {
  local implementation="$1" source="$2" binary="$3" log="$4"
  if [[ "$implementation" == original ]]; then
    local -a link_flags=()
    if [[ -n "${ORIGINAL_CRYSTAL_LINK_FLAGS:-}" ]]; then
      link_flags+=("--link-flags=$ORIGINAL_CRYSTAL_LINK_FLAGS")
    fi
    "$SAFE" "$ORIGINAL" 45 4096 build --prelude=empty "$source" "${link_flags[@]}" -o "$binary" >"$log" 2>&1
  else
    "$SAFE" "$CANDIDATE" 45 4096 "$source" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1
  fi
}

run_positive() {
  local implementation="$1" case_name="$2" expected="$3"
  local source="$FIXTURES/$case_name.cr"
  local binary="$WORK/$implementation-$case_name" log="$WORK/$implementation-$case_name.compile.log"
  compile "$implementation" "$source" "$binary" "$log" || { cat "$log" >&2; return 1; }
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 5 512 >"$WORK/$implementation-$case_name.stdout" 2>"$WORK/$implementation-$case_name.run.log" || {
    cat "$WORK/$implementation-$case_name.run.log" >&2; return 1;
  }
  printf '%s' "$expected" >"$WORK/$case_name.expected"
  cmp -s "$WORK/$case_name.expected" "$WORK/$implementation-$case_name.stdout" || {
    printf 'FAIL %s %s: expected %q, got %q\n' "$implementation" "$case_name" "$expected" "$(cat "$WORK/$implementation-$case_name.stdout")" >&2
    cat "$log" >&2
    return 1
  }
  echo "PASS $implementation $case_name"
}

run_negative() {
  local implementation="$1" case_name="$2" original_fragment="$3" candidate_fragment="$4"
  local source="$FIXTURES/$case_name.cr"
  local binary="$WORK/$implementation-$case_name" log="$WORK/$implementation-$case_name.compile.log"
  if compile "$implementation" "$source" "$binary" "$log"; then
    echo "FAIL $implementation $case_name: compile unexpectedly succeeded" >&2
    return 1
  fi
  [[ ! -e "$binary" ]] || { echo "FAIL $implementation $case_name: binary was emitted" >&2; return 1; }
  if [[ "$implementation" == original ]]; then
    grep -Fq "$original_fragment" "$log" || {
      echo "FAIL original $case_name: missing expected type diagnostic" >&2
      cat "$log" >&2
      return 1
    }
  else
    grep -Fq "$candidate_fragment" "$log" || {
      echo "FAIL candidate $case_name: missing union argument rejection" >&2
      cat "$log" >&2
      return 1
    }
  fi
  echo "PASS $implementation $case_name"
}

implementations=()
if [[ "${CANDIDATE_ONLY:-0}" != 1 ]]; then
  implementations+=(original)
fi
if [[ "${ORIGINAL_ONLY:-0}" != 1 ]]; then
  implementations+=(candidate)
fi
if [[ "${#implementations[@]}" -eq 0 ]]; then
  echo "ERROR: ORIGINAL_ONLY and CANDIDATE_ONLY cannot both be 1" >&2
  exit 2
fi
failures=0
for implementation in "${implementations[@]}"; do
  run_positive "$implementation" dispatch $'U\n' || failures=1
  run_positive "$implementation" alias_union $'U\n' || failures=1
  run_positive "$implementation" local_typeof $'U\n' || failures=1
  run_positive "$implementation" dynamic_metaclass_union $'VV\n' || failures=1
  run_positive "$implementation" generic_type_object_shape $'AAAAGG\n' || failures=1
  run_negative "$implementation" reject_scalar_only \
    "expected argument #1 to 'pick' to be Bool.class or Int32.class, not (Bool | Int32).class" \
    "no overload matches pick" || failures=1
  run_negative "$implementation" reject_complete_union_class_as_metaclass_union \
    "expected argument #1 to 'accept' to be (Bool.class | Int32.class), not (Bool | Int32).class" \
    "no overload matches accept" || failures=1
  run_negative "$implementation" reject_generic_dynamic_metaclass_union \
    "expected argument #1 to 'accept_type_object' to be Bool.class, not (Bool.class | Int32.class)" \
    "no overload matches accept_type_object" || failures=1
  run_negative "$implementation" reject_generic_instance_union \
    "expected argument #1 to 'accept_type_object' to be T.class, not (Bool | Int32)" \
    "no overload matches accept_type_object" || failures=1
  run_positive "$implementation" dynamic_union $'BI\n' || failures=1
done
exit "$failures"
