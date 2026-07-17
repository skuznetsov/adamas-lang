#!/usr/bin/env bash
# RED/GREEN oracle for inherited virtual-demand amplification.
#
# The no-override contract is one implementation body regardless of the number
# of live empty descendants. A real override remains a separate implementation
# and keeps a dispatcher. This reducer deliberately inspects HIR/MIR identity,
# not raw LLVM function totals.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/inherited_virtual_demand_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

make_source() {
  local mode="$1"
  local descendants="$2"
  local src="$3"
  {
    printf '%s\n' 'class Object' 'end' ''
    printf '%s\n' 'class Parent < Object' '  def value(x : Int32) : Int32' '    x' '  end'
    if [[ "$mode" == overload ]]; then
      printf '%s\n' '  def value(x : UInt64) : Int32' '    9' '  end'
    fi
    printf '%s\n' 'end' ''
    local i
    for ((i = 0; i < descendants; i++)); do
      if [[ "$mode" == override && "$i" -eq 0 ]]; then
        printf 'class Child%d < Parent\n  def value(x : Int32) : Int32\n    42\n  end\nend\n\n' "$i"
      else
        printf 'class Child%d < Parent\nend\n\n' "$i"
      fi
    done
    if [[ "$mode" == generic ]]; then
      printf '%s\n' 'class Box(T) < Parent' 'end' ''
      printf '%s\n' 'def invoke_generic(parent : Parent, x : Int32) : Int32' '  parent.value(x)' 'end' ''
      printf '%s\n' 'invoke_generic(Box(Int32).new.as(Parent), 7)'
    else
      printf '%s\n' 'def invoke_static(parent : Parent, x : Int32) : Int32' '  parent.value(x)' 'end' ''
      printf '%s\n' 'def invoke_dynamic(parent : Parent, x : Int32) : Int32' '  parent.value(x)' 'end' ''
      if [[ "$mode" == overload ]]; then
        printf '%s\n' 'def invoke_overload(parent : Parent, x : UInt64) : Int32' '  parent.value(x)' 'end' ''
      fi
      if [[ "$descendants" -gt 0 ]]; then
        printf '%s\n' 'invoke_static(Parent.new, 1)'
        local j
        for ((j = 0; j < descendants; j++)); do
          printf 'invoke_dynamic(Child%d.new.as(Parent), %d)\n' "$j" "$((j + 2))"
        done
        if [[ "$mode" == overload ]]; then
          printf '%s\n' 'invoke_overload(Child0.new.as(Parent), 9_u64)'
        fi
      else
        printf '%s\n' 'invoke_static(Parent.new, 1)' 'invoke_dynamic(Parent.new, 2)'
        if [[ "$mode" == overload ]]; then
          printf '%s\n' 'invoke_overload(Parent.new, 9_u64)'
        fi
      fi
    fi
  } >"$src"
}

compile_hir_mir() {
  local src="$1"
  local out="$2"
  "$RUN_SAFE" "$COMPILER" 60 2048 "$src" --no-prelude --emit hir --emit mir \
    --no-link --no-llvm-opt --no-llvm-cache -o "$out" >"$out.log" 2>&1
}

assert_no_override() {
  local d="$1"
  local src="$TMP_DIR/no_override_${d}.cr"
  local out="$TMP_DIR/no_override_${d}"
  make_source no_override "$d" "$src"
  compile_hir_mir "$src" "$out"
  local hir="$out.hir"
  local mir="$out.mir"
  local body_count child_count dispatch_count
  body_count="$(grep -Ec '^func @[^ ]*#value\$Int32' "$hir" || true)"
  child_count="$(grep -Ec '^func @Child[0-9]+#value\$Int32' "$hir" || true)"
  dispatch_count="$(grep -Ec '^func @__vdispatch__Parent#value\$Int32' "$mir" || true)"
  echo "no_override d=$d body=$body_count child_body=$child_count dispatch=$dispatch_count"
  # This is expected to be RED on the pre-fix compiler: child_body is d and
  # dispatch is 1. Keep the assertion as the production contract.
  if [[ "$body_count" -ne 1 || "$child_count" -ne 0 ]]; then
    echo "inherited_virtual_demand_amplifier_failed: no-override body fanout at d=$d" >&2
    return 1
  fi
  if [[ "$dispatch_count" -ne 0 ]]; then
    echo "inherited_virtual_demand_amplifier_failed: unified implementation still dispatches at d=$d" >&2
    return 1
  fi
}

assert_override_and_negative_controls() {
  local src="$TMP_DIR/override.cr"
  local out="$TMP_DIR/override"
  make_source override 8 "$src"
  compile_hir_mir "$src" "$out"
  local hir="$out.hir"
  local mir="$out.mir"
  local body_count child0_count child1_count dispatch_count
  body_count="$(grep -Ec '^func @[^ ]*#value\$Int32' "$hir" || true)"
  child0_count="$(grep -Ec '^func @Child0#value\$Int32' "$hir" || true)"
  child1_count="$(grep -Ec '^func @Child1#value\$Int32' "$hir" || true)"
  dispatch_count="$(grep -Ec '^func @__vdispatch__Parent#value\$Int32' "$mir" || true)"
  echo "override d=8 body=$body_count child0_body=$child0_count child1_body=$child1_count dispatch=$dispatch_count"
  if [[ "$body_count" -ne 2 || "$child0_count" -ne 1 || "$child1_count" -ne 0 || "$dispatch_count" -ne 1 ]]; then
    echo "inherited_virtual_demand_amplifier_failed: override identity/dispatch contract" >&2
    return 1
  fi

  src="$TMP_DIR/generic.cr"
  out="$TMP_DIR/generic"
  make_source generic 8 "$src"
  compile_hir_mir "$src" "$out"
  hir="$out.hir"
  mir="$out.mir"
  if grep -q '^func @Box(Int32)#value\$Int32' "$hir"; then
    echo "inherited_virtual_demand_amplifier_failed: generic inherited wrapper was synthesized" >&2
    return 1
  fi
  local generic_parent_count generic_dispatch_count
  generic_parent_count="$(grep -Ec '^func @Parent#value\$Int32' "$hir" || true)"
  generic_dispatch_count="$(grep -Ec '^func @__vdispatch__Parent#value\$Int32' "$mir" || true)"
  if [[ "$generic_parent_count" -ne 1 || "$generic_dispatch_count" -ne 0 ]]; then
    echo "inherited_virtual_demand_amplifier_failed: generic inherited dispatch widened" >&2
    return 1
  fi
  echo "generic negative_control=pass"

  src="$TMP_DIR/overload.cr"
  out="$TMP_DIR/overload"
  make_source overload 8 "$src"
  compile_hir_mir "$src" "$out"
  hir="$out.hir"
  mir="$out.mir"
  local int32_count uint64_count
  local child_int32_count child_uint64_count int32_dispatch_count uint64_dispatch_count
  int32_count="$(grep -Ec '^func @Parent#value\$Int32' "$hir" || true)"
  uint64_count="$(grep -Ec '^func @Parent#value\$UInt64' "$hir" || true)"
  child_int32_count="$(grep -Ec '^func @Child[0-9]+#value\$Int32' "$hir" || true)"
  child_uint64_count="$(grep -Ec '^func @Child[0-9]+#value\$UInt64' "$hir" || true)"
  int32_dispatch_count="$(grep -Ec '^func @__vdispatch__Parent#value\$Int32' "$mir" || true)"
  uint64_dispatch_count="$(grep -Ec '^func @__vdispatch__Parent#value\$UInt64' "$mir" || true)"
  echo "overload d=8 int32=$int32_count uint64=$uint64_count child_int32=$child_int32_count child_uint64=$child_uint64_count int32_dispatch=$int32_dispatch_count uint64_dispatch=$uint64_dispatch_count"
  if [[ "$int32_count" -ne 1 || "$uint64_count" -ne 1 ||
        "$child_int32_count" -ne 0 || "$child_uint64_count" -ne 0 ||
        "$int32_dispatch_count" -ne 0 || "$uint64_dispatch_count" -ne 0 ]]; then
    echo "inherited_virtual_demand_amplifier_failed: overload identity collapsed or over-demanded" >&2
    return 1
  fi
  echo "overload negative_control=pass"
}

for d in 0 1 8 16; do
  assert_no_override "$d"
done
assert_override_and_negative_controls
echo "inherited_virtual_demand_amplifier_no_prelude_ok"
