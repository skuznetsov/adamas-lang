#!/usr/bin/env bash
# Reproduce the stale scalar UnionWrap hint that corrupted Parser#expect_operator.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/union-wrap-actual.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cd "$root"
CRYSTAL_CACHE_DIR="$work/cache" "$root/scripts/run_safe.sh" "${CRYSTAL:-crystal}" 120 8192 \
  spec spec/mir/union_wrap_actual_representation_spec.cr
