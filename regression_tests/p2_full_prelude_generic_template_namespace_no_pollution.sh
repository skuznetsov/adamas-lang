#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-bin/adamas}"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d /tmp/cv2_generic_template_ns.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/hello.cr" <<'CR'
puts 42
CR

log="$tmpdir/hello.log"
set +e
CRYSTAL_V2_TRACE_CLASS_FRONTIER=1 \
DEBUG_GENERIC_TEMPLATE=1 \
  "$root_dir/scripts/run_safe.sh" "$compiler" 120 4096 "$tmpdir/hello.cr" -o "$tmpdir/hello_bin" \
  >"$log" 2>&1
set -e

bad_patterns=(
  'Crystal::PointerLinkedList::Crystal::PointerLinkedList'
  'Exception::CallStack::Exception::CallStack'
  'Float::FastFloat::Float::FastFloat'
  'resolved=Float::FastFloat::String'
  'resolved=Float::FastFloat::Bool'
  'type=Float::FastFloat::String'
  'type=Float::FastFloat::Bool'
  'Indexable::Indexable'
  '[GENERIC_TEMPLATE] Iterator:::'
  '[GENERIC_TEMPLATE] Steppable:::'
  '[GENERIC_TEMPLATE] Indexable:::'
)

for pattern in "${bad_patterns[@]}"; do
  if grep -Fq "$pattern" "$log"; then
    echo "p2 generic template namespace pollution: found $pattern" >&2
    tail -120 "$log" >&2
    exit 1
  fi
done

required_patterns=(
  'nested_module_def_param_type Float::FastFloat.to_f64? raw=String resolved=String type=String'
  'nested_module_def_param_type Float::FastFloat.to_f64? raw=Bool resolved=Bool type=Bool'
  'nested_module_def_param_type Float::FastFloat.to_f32? raw=String resolved=String type=String'
  'nested_module_def_param_type Float::FastFloat.to_f32? raw=Bool resolved=Bool type=Bool'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$log"; then
    echo "p2 generic template namespace pollution: missing $pattern" >&2
    tail -120 "$log" >&2
    exit 1
  fi
done

echo "p2_full_prelude_generic_template_namespace_no_pollution_ok"
