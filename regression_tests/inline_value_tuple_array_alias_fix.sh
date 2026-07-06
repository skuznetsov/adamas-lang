#!/usr/bin/env bash
# Inline-value tuple ABI BEHAVIOR regression — the Array(Tuple) @buffer alias fix
# (memory: inline_tuple_slot_layout_site_census; docs/inline_value_tuple_abi_sdd.md).
#
# A pod-tuple element read from an Array buffer is, under the legacy carrier ABI, a
# BORROW pointer into @buffer (PointerCarrier). Any live use that outlives a buffer
# mutation is then corrupted. Both gates together break the borrow — the element is
# stored inline and copied on load:
#   ADAMAS_INLINE_VALUE_TUPLE          -> pod_tuple? classified InlineValueCopy candidate
#   ADAMAS_INLINE_VALUE_ARRAY_STORAGE  -> A' inline store + copy-on-load behavior slice
#
# Three facets, each: legacy MIScompiles, both-gates fixes. DoD per case:
#   - both-gates output == expected;
#   - legacy output != gated output (the reducer actually exercises the fix).
# The reducer prints to unbuffered STDERR + flush so the runtime last-write
# truncation cannot eat the assertion line. Inline heredocs (no scanned *.cr) so the
# known-buggy-at-default sources never enter the default clean-exit suite.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
GATES=(ADAMAS_INLINE_VALUE_TUPLE=1 ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1)

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ivtaf.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
fail=0

# mode=coupled : legacy MIScompiles (asserts legacy != gated) — documents a facet
#                only the gates fix (copy-on-load local bind).
# mode=fixed   : the default path is FIXED (ArrayNew stride + ctor copy-at-escape,
#                2026-07-06) — asserts legacy == gated == expected.
check() {
  local mode="$1" name="$2" expect="$3" src="$4"
  local f="$TMP_DIR/$name.cr"
  printf '%s\n' "$src" > "$f"
  "$COMPILER" "$f" -o "$TMP_DIR/$name.legacy" >/dev/null 2>/dev/null \
    || { echo "FAIL[$name]: legacy compile failed"; fail=1; return; }
  env "${GATES[@]}" "$COMPILER" "$f" -o "$TMP_DIR/$name.gated" >/dev/null 2>/dev/null \
    || { echo "FAIL[$name]: gated compile failed"; fail=1; return; }
  local L G
  L="$("$RUNNER" "$TMP_DIR/$name.legacy" 5 256 2>&1 | grep RESULT || true)"
  G="$("$RUNNER" "$TMP_DIR/$name.gated"  5 256 2>&1 | grep RESULT || true)"
  echo "  [$name/$mode] legacy='$L'  gated='$G'"
  if [[ "$G" != "$expect" ]]; then echo "FAIL[$name]: gated '$G' != expected '$expect'"; fail=1; fi
  if [[ "$mode" == "fixed" ]]; then
    if [[ "$L" != "$expect" ]]; then echo "FAIL[$name]: legacy '$L' != expected '$expect' (default-path regression)"; fail=1; fi
  else
    if [[ "$L" == "$G" ]]; then echo "FAIL[$name]: legacy==gated — reducer no longer exercises the fix"; fail=1; fi
  fi
}

echo "compiler: $COMPILER"

# sort_by! on Array(Tuple): writeback overwrites @buffer while sorted slots
# still borrow it -> the last element duplicates. FIXED on the default path by
# the tuple-ctor copy-at-escape (hir_to_mir lower_allocate).
check fixed sort "RESULT: 2,50 3,75 1,100" 'items = [{1, 100}, {2, 50}, {3, 75}]
items.sort_by! { |e| e[1] }
parts = items.map { |t| "#{t[0]},#{t[1]}" }
STDERR.puts "RESULT: #{parts.join(" ")}"
STDERR.flush'

# (ADV1) local binding a = arr[i]: overwriting the source slot must not change a.
# FIXED on the default path by the ungated inline-primitive-tuple array_get
# copy-on-load (4ea2fc66).
check fixed adv1 "RESULT: 1,100" 'arr = [{1, 100}, {2, 50}, {3, 75}]
a = arr[0]
arr[0] = {9, 9}
STDERR.puts "RESULT: #{a[0]},#{a[1]}"
STDERR.flush'

# (ADV3) construction {arr[i], k}: the inner element must be copied into the outer
# tuple, not stored as a borrow into @buffer. FIXED on the default path by the
# tuple-ctor copy-at-escape.
check fixed adv3 "RESULT: 1,100 2,50 3,75" 'arr = [{1, 100}, {2, 50}, {3, 75}]
mapped = arr.map { |e| {e, 0} }
arr[0] = {9, 9}
arr[1] = {9, 9}
arr[2] = {9, 9}
res = mapped.map { |m| inner = m[0]; "#{inner[0]},#{inner[1]}" }
STDERR.puts "RESULT: #{res.join(" ")}"
STDERR.flush'

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok: Array(Tuple) @buffer alias fixed on default AND gated across sort/local-bind/construct facets"
exit 0
