#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-}"
if [[ -z "$compiler" || ! -x "$compiler" ]]; then
  echo "usage: $0 /path/to/crystal_v2_or_produced_s2" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_base="$(mktemp /tmp/cv2_prescan_frontier_src_XXXXXX)"
src="${src_base}.cr"
out_bin="$(mktemp /tmp/cv2_prescan_frontier_bin_XXXXXX)"
log="$(mktemp /tmp/cv2_prescan_frontier_log_XXXXXX)"
rm -f "$src_base" "$src" "$out_bin"
trap 'rm -f "$src_base" "$src" "$out_bin" "$log"' EXIT

printf 'puts 42\n' > "$src"

set +e
"$repo_root/scripts/run_safe.sh" "$compiler" 120 4096 "$src" -o "$out_bin" >"$log" 2>&1
status=$?
set -e

if ! grep -q '\[STAGE2_DEBUG\] pre-scan constants done' "$log"; then
  echo "expected compiler to pass class/module constant pre-scan; exit=$status" >&2
  tail -120 "$log" >&2
  exit 1
fi

if grep -q 'store ptr 32768' "$log"; then
  echo "pre-scan scalar constants lost type metadata (store ptr 32768 regression)" >&2
  tail -120 "$log" >&2
  exit 1
fi

echo "p2_prescan_complex_constants_frontier_ok"
