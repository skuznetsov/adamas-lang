#!/usr/bin/env bash
# Emit, normalize, and compare HIR/MIR/LLVM IR across bootstrap stages.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE_DIR="${1:-/tmp/crystal_v2_bootstrap_stages}"
CORPUS="${2:-$ROOT_DIR/regression_tests/bootstrap_semantic_corpus.cr}"
OUT_DIR="${3:-/tmp/crystal_v2_bootstrap_ir}"

stages=(s1_bootstrap s2b s3b s4b s5b)
kinds=(hir mir ll)

usage() {
  cat <<'USAGE'
Usage:
  scripts/compare_bootstrap_stages.sh [stage-dir] [corpus.cr] [out-dir]

Expected stage artifacts in stage-dir:
  s1_bootstrap, s2b, s3b, s4b, s5b

Fallback accepted:
  cv2_s1, cv2_s2, cv2_s3, cv2_s4, cv2_s5
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -d "$STAGE_DIR" ]]; then
  echo "error: stage dir not found: $STAGE_DIR" >&2
  exit 2
fi
if [[ ! -f "$CORPUS" ]]; then
  echo "error: corpus not found: $CORPUS" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

stage_path() {
  local idx="$1"
  local name="${stages[$idx]}"
  local fallback="$STAGE_DIR/cv2_s$((idx + 1))"
  if [[ -x "$STAGE_DIR/$name" ]]; then
    printf '%s\n' "$STAGE_DIR/$name"
  elif [[ -x "$fallback" ]]; then
    printf '%s\n' "$fallback"
  else
    echo "error: missing executable for ${name} (or $fallback)" >&2
    return 1
  fi
}

for idx in "${!stages[@]}"; do
  stage="${stages[$idx]}"
  compiler="$(stage_path "$idx")"
  prefix="$OUT_DIR/$stage"
  "$ROOT_DIR/scripts/emit_bootstrap_ir.sh" "$compiler" "$CORPUS" "$prefix"
  for kind in "${kinds[@]}"; do
    "$ROOT_DIR/scripts/normalize_bootstrap_ir.sh" "$prefix.$kind" >"$prefix.$kind.norm"
  done
done

base="${stages[0]}"
for stage in "${stages[@]:1}"; do
  for kind in "${kinds[@]}"; do
    if ! diff -u "$OUT_DIR/$base.$kind.norm" "$OUT_DIR/$stage.$kind.norm" >"$OUT_DIR/$base-vs-$stage.$kind.diff"; then
      echo "SEMANTIC_DIFF: $base vs $stage ($kind)" >&2
      echo "diff: $OUT_DIR/$base-vs-$stage.$kind.diff" >&2
      exit 1
    fi
  done
done

echo "SEMANTIC_EQ: S1..S5 ok corpus=$CORPUS out=$OUT_DIR"
