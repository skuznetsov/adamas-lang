#!/usr/bin/env bash
# Same-source runtime oracle for the bounded inherited virtual-demand slice.
#
# Usage:
#   inherited_virtual_demand_runtime_oracle.sh <adamas-compiler> <original-crystal>
#
# Both compiler invocations and all produced binaries run through run_safe.
# The source deliberately uses LibC.exit rather than prelude-dependent output,
# so the original and Adamas compilers consume the same no-prelude program.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAMAS_COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${2:-${ORIGINAL_CRYSTAL:-crystal}}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inherited_virtual_runtime_XXXXXX")"
LEDGER_OUT="${INHERITED_RUNTIME_LEDGER:-}"
LLVM_OUT_DIR="${INHERITED_RUNTIME_LLVM_DIR:-}"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ -n "$LEDGER_OUT" ]]; then
  : >"$LEDGER_OUT"
fi
if [[ -n "$LLVM_OUT_DIR" ]]; then
  mkdir -p "$LLVM_OUT_DIR"
fi

if [[ ! -x "$ADAMAS_COMPILER" ]]; then
  echo "ERROR: Adamas compiler not found: $ADAMAS_COMPILER" >&2
  exit 2
fi
if ! command -v "$ORIGINAL_CRYSTAL" >/dev/null 2>&1 && [[ ! -x "$ORIGINAL_CRYSTAL" ]]; then
  echo "ERROR: original Crystal compiler not found: $ORIGINAL_CRYSTAL" >&2
  exit 2
fi

make_source() {
  local mode="$1"
  local descendants="$2"
  local src="$3"
  {
    printf '%s\n' 'class Object' 'end' ''
    printf '%s\n' 'lib LibC' '  fun exit(status : Int32) : NoReturn' 'end' ''
    printf '%s\n' 'class Parent < Object' '  def value(x : Int32) : Int32' '    x' '  end'
    if [[ "$mode" == overload ]]; then
      printf '%s\n' '  def value(x : UInt64) : Int32' '    42' '  end'
    fi
    printf '%s\n' 'end' ''
    local i
    for ((i = 0; i < descendants; i++)); do
      if [[ "$mode" == override && "$i" -eq 0 ]]; then
        printf '%s\n' "class Child$i < Parent" '  def value(x : Int32) : Int32' '    42' '  end' 'end' ''
      else
        printf '%s\n' "class Child$i < Parent" 'end' ''
      fi
    done

    case "$mode" in
      generic)
        printf '%s\n' 'class Box(T) < Parent' 'end' ''
        printf '%s\n' 'def invoke(parent : Parent, x : Int32) : Int32' '  parent.value(x)' 'end' ''
        printf '%s\n' 'LibC.exit(invoke(Box(Int32).new.as(Parent), 41))'
        ;;
      overload)
        # Both overload shapes are demanded and checked; a collapsed or wrong
        # overload returns status 1 instead of the expected status 0.
        printf '%s\n' 'def exercise(parent : Parent) : Int32' '  a = parent.value(41)' '  b = parent.value(9_u64)' '  if a == 41 && b == 42' '    0' '  else' '    1' '  end' 'end' ''
        if [[ "$descendants" -gt 0 ]]; then
          printf '%s\n' 'LibC.exit(exercise(Child0.new.as(Parent)))'
        else
          printf '%s\n' 'LibC.exit(exercise(Parent.new))'
        fi
        ;;
      override)
        printf '%s\n' 'LibC.exit(Child0.new.as(Parent).value(41))'
        ;;
      *)
        if [[ "$descendants" -gt 0 ]]; then
          printf '%s\n' 'LibC.exit(Child0.new.as(Parent).value(41))'
        else
          printf '%s\n' 'LibC.exit(Parent.new.value(41))'
        fi
        ;;
    esac
  } >"$src"
}

run_case() {
  local mode="$1"
  local descendants="$2"
  local tag="${mode}_${descendants}"
  local src="$WORK_DIR/$tag.cr"
  local adamas_bin="$WORK_DIR/$tag.adamas.bin"
  local original_bin="$WORK_DIR/$tag.original.bin"
  local adamas_compile_log="$WORK_DIR/$tag.adamas.compile.log"
  local original_compile_log="$WORK_DIR/$tag.original.compile.log"
  local adamas_run_log="$WORK_DIR/$tag.adamas.run.log"
  local original_run_log="$WORK_DIR/$tag.original.run.log"
  local adamas_llvm_rc=0
  local original_llvm_rc=0
  local adamas_ll=""
  local original_ll=""

  make_source "$mode" "$descendants" "$src"

  set +e
  "$RUN_SAFE" "$ADAMAS_COMPILER" 60 4096 "$src" --no-prelude -o "$adamas_bin" >"$adamas_compile_log" 2>&1
  local adamas_compile_rc=$?
  if [[ $adamas_compile_rc -eq 0 ]]; then
    "$RUN_SAFE" "$adamas_bin" 5 512 >"$adamas_run_log" 2>&1
    local adamas_run_rc=$?
  else
    local adamas_run_rc=125
  fi

  env CRYSTAL_CACHE_DIR="$WORK_DIR/original_cache_$tag" \
    "$RUN_SAFE" "$ORIGINAL_CRYSTAL" 60 4096 build "$src" --prelude=empty -O0 --single-module -o "$original_bin" >"$original_compile_log" 2>&1
  local original_compile_rc=$?
  if [[ $original_compile_rc -eq 0 ]]; then
    "$RUN_SAFE" "$original_bin" 5 512 >"$original_run_log" 2>&1
    local original_run_rc=$?
  else
    local original_run_rc=125
  fi

  # Optional same-source LLVM pair. Keep this in the runtime oracle so the
  # exact source, compiler flags, and runtime row remain tied together. The
  # forward classifier consumes these files later; this script only records
  # compile status and content identities.
  if [[ -n "$LLVM_OUT_DIR" ]]; then
    adamas_ll="$LLVM_OUT_DIR/$tag.adamas.ll"
    # Crystal's --emit=llvm-ir writes the sidecar as <output-prefix>.ll
    # (and may also leave the requested prefix executable); Adamas writes the
    # requested prefix plus .ll. Keep only the IR identity in the ledger.
    original_ll="$LLVM_OUT_DIR/$tag.ll"
    rm -f "$adamas_ll" "$original_ll" "$LLVM_OUT_DIR/$tag.original"
    set +e
    "$RUN_SAFE" "$ADAMAS_COMPILER" 60 4096 "$src" --no-prelude --emit llvm-ir --no-link --no-llvm-opt --no-llvm-cache -o "$LLVM_OUT_DIR/$tag.adamas" >"$WORK_DIR/$tag.adamas.llvm.log" 2>&1
    adamas_llvm_rc=$?
    env CRYSTAL_CACHE_DIR="$WORK_DIR/original_llvm_cache_$tag" \
      "$RUN_SAFE" "$ORIGINAL_CRYSTAL" 60 4096 build "$src" --prelude=empty --emit=llvm-ir --no-debug -O0 --single-module -o "$LLVM_OUT_DIR/$tag.original" >"$WORK_DIR/$tag.original.llvm.log" 2>&1
    original_llvm_rc=$?
    set -e
  fi
  set -e

  if [[ -n "$LLVM_OUT_DIR" && ( ! -s "$adamas_ll" || ! -s "$original_ll" ) ]]; then
    echo "inherited_virtual_demand_runtime_oracle_failed: missing LLVM pair for $tag" >&2
    printf 'expected_adamas_ll=%s\nexpected_original_ll=%s\n' "$adamas_ll" "$original_ll" >&2
    return 1
  fi

  local source_sha="unknown"
  local adamas_bin_sha="unknown"
  local original_bin_sha="unknown"
  local adamas_llvm_sha="unknown"
  local original_llvm_sha="unknown"
  if command -v shasum >/dev/null 2>&1; then
    source_sha="$(shasum -a 256 "$src" | awk '{print $1}')"
    if [[ -f "$adamas_bin" ]]; then
      adamas_bin_sha="$(shasum -a 256 "$adamas_bin" | awk '{print $1}')"
    fi
    if [[ -f "$original_bin" ]]; then
      original_bin_sha="$(shasum -a 256 "$original_bin" | awk '{print $1}')"
    fi
    if [[ -n "$adamas_ll" && -f "$adamas_ll" ]]; then
      adamas_llvm_sha="$(shasum -a 256 "$adamas_ll" | awk '{print $1}')"
    fi
    if [[ -n "$original_ll" && -f "$original_ll" ]]; then
      original_llvm_sha="$(shasum -a 256 "$original_ll" | awk '{print $1}')"
    fi
  fi
  local ledger_line="runtime mode=$mode d=$descendants adamas_compile=$adamas_compile_rc adamas_exit=$adamas_run_rc original_compile=$original_compile_rc original_exit=$original_run_rc adamas_llvm_compile=$adamas_llvm_rc original_llvm_compile=$original_llvm_rc source_sha256=$source_sha adamas_bin_sha256=$adamas_bin_sha original_bin_sha256=$original_bin_sha adamas_llvm_sha256=$adamas_llvm_sha original_llvm_sha256=$original_llvm_sha"
  echo "$ledger_line"
  if [[ -n "$LEDGER_OUT" ]]; then
    echo "$ledger_line" >>"$LEDGER_OUT"
  fi
  if [[ $adamas_compile_rc -ne 0 || $original_compile_rc -ne 0 ||
        $adamas_run_rc -ne $original_run_rc ||
        $adamas_llvm_rc -ne 0 || $original_llvm_rc -ne 0 ]]; then
    echo "inherited_virtual_demand_runtime_oracle_failed: $tag" >&2
    tail -n 30 "$adamas_compile_log" "$adamas_run_log" "$original_compile_log" "$original_run_log" >&2 || true
    return 1
  fi
}

for descendants in 0 1 8 16; do
  run_case no_override "$descendants"
done
run_case override 8
run_case generic 8
run_case overload 8
echo "inherited_virtual_demand_runtime_oracle_ok"
