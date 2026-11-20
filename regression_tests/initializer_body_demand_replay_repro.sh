#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
CRYSTAL_BIN_PATH="${CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/initializer-body-replay.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# These parsed-source HIR tests lower with a bounded force budget, then resume
# the actual initializer body demand. Internal queue/source mutation controls
# check strict refusal separately from native source-result regressions.
SPEC_ARGS=(spec --no-color
  "$ROOT_DIR/spec/hir/force_lower_dependency_queue_spec.cr"
  "$ROOT_DIR/spec/hir/force_lower_active_edge_graph_spec.cr"
  "$ROOT_DIR/spec/hir/recursive_result_projection_spec.cr"
  "$ROOT_DIR/spec/hir/initializer_body_pending_replay_spec.cr"
  "$ROOT_DIR/spec/hir/initializer_sequential_replay_spec.cr"
  "$ROOT_DIR/spec/hir/bound_initializer_result_replay_spec.cr"
  "$ROOT_DIR/spec/hir/static_nilary_result_replay_spec.cr"
  --single-module -D debug_hooks --error-trace)
if [[ -n "${ADAMAS_EXTRA_LINK_FLAGS:-}" ]]; then
  SPEC_ARGS+=("--link-flags=$ADAMAS_EXTRA_LINK_FLAGS")
fi
CRYSTAL_CACHE_DIR="$WORK/cache" TMPDIR="$WORK" \
  "$ROOT_DIR/scripts/run_safe.sh" "$CRYSTAL_BIN_PATH" 180 14336 "${SPEC_ARGS[@]}"

printf 'PASS: exact initializer body demands and dependency replay guards\n'
