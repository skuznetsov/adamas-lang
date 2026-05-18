#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="$1"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cv2_each_key_fallback.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

1.0_f32.each_key do |x|
  x
end

LibC.exit(0)
CR

log="$tmpdir/repro.log"
out="$tmpdir/repro"

"$ROOT_DIR/scripts/run_safe.sh" "$compiler" 60 2048 \
  "$tmpdir/repro.cr" --no-prelude --emit llvm-ir --no-link -o "$out" \
  >"$log" 2>&1

if [[ ! -s "$out.ll" ]]; then
  echo "each_key fallback guard did not emit LLVM IR" >&2
  tail -120 "$log" >&2 || true
  exit 1
fi

if grep -Eq 'ret ptr %arg0' "$out.ll"; then
  echo "each_key fallback guard found ptr return from unchecked primitive arg0" >&2
  grep -n -A4 -B2 'Heach_key[$][$]block' "$out.ll" >&2 || true
  exit 1
fi

grep -Eq 'define ptr @Float32[$]Heach_key[$][$]block[(]float %arg0, ptr %arg1[)]' "$out.ll"
grep -Eq 'ret ptr null' "$out.ll"

echo "p2_each_key_fallback_primitive_return_shape_ok"
