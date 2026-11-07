#!/usr/bin/env bash
# Declaration generics and a selected initializer's call context have separate
# owners. Exercise foreign shared hints, exact specialization maps, retirement,
# stale-source/ABI rejection, and native initializer results.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT/bin/adamas}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-crystal}"
SAFE="$ROOT/scripts/run_safe.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/initializer_binding_owner.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

if [[ -z "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_PATH="$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$ORIGINAL" 10 1024 env CRYSTAL_PATH)"
  export CRYSTAL_PATH
fi
export CRYSTAL_CACHE_DIR="$WORK/cache"
flags=()
if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then
  flags+=("--link-flags=$ORIGINAL_LINK_FLAGS")
elif [[ "$(uname -s)" == Darwin ]]; then
  flags+=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ORIGINAL_LINK_FLAGS=-fuse-ld=/usr/bin/ld
fi
(cd "$ROOT" && "$SAFE" "$ORIGINAL" 180 14336 spec \
  spec/hir/materialized_initializer_source_spec.cr \
  spec/hir/initializer_layout_replay_spec.cr \
  spec/hir/pending_queue_layout_invalidation_spec.cr \
  "${flags[@]}" --single-module --no-debug) > "$WORK/spec.log" 2>&1 || {
  cat "$WORK/spec.log" >&2
  exit 1
}
cat "$WORK/spec.log"
bash "$ROOT/regression_tests/initializer_return_replay_repro.sh" "$COMPILER"
echo "PASS: initializer replay binding ownership and native result controls"
