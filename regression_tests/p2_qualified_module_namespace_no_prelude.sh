#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-bin/crystal_v2}"
tmpdir="$(mktemp -d /tmp/cv2_qualified_module_ns.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/repro.cr" <<'CR'
module Float::FastFloat
  struct ParsedNumberStringT(UC)
  end
end
CR

log="$tmpdir/repro.log"
CRYSTAL_V2_STOP_AFTER_HIR=1 \
CRYSTAL_V2_TRACE_CLASS_FRONTIER=1 \
  scripts/run_safe.sh "$compiler" 20 1024 "$tmpdir/repro.cr" --no-prelude -o "$tmpdir/repro" \
  >"$log" 2>&1

if grep -q 'Float::Float::ParsedNumberStringT' "$log"; then
  echo "unexpected duplicated Float namespace" >&2
  tail -80 "$log" >&2
  exit 1
fi

if grep -q 'Float::FastFloat::Float::FastFloat' "$log"; then
  echo "unexpected duplicated qualified module namespace" >&2
  tail -80 "$log" >&2
  exit 1
fi

grep -q 'Float::FastFloat::ParsedNumberStringT' "$log"
echo "p2_qualified_module_namespace_no_prelude_ok"
