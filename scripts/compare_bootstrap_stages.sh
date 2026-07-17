#!/usr/bin/env bash
# Emit, normalize, and compare HIR/MIR/LLVM IR across bootstrap stages.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE_DIR="${1:-/tmp/adamas_bootstrap_stages}"
CORPUS="${2:-$ROOT_DIR/regression_tests/bootstrap_semantic_corpus.cr}"
OUT_DIR="${3:-/tmp/adamas_bootstrap_ir}"
STAGE_COUNT="${BOOTSTRAP_COMPARE_STAGE_COUNT:-5}"

all_stages=(s1_bootstrap s2b s3b s4b s5b)
stages=()
kinds=(hir mir ll)

usage() {
  cat <<'USAGE'
Usage:
  scripts/compare_bootstrap_stages.sh [stage-dir] [corpus.cr] [out-dir]

Environment:
  BOOTSTRAP_COMPARE_STAGE_COUNT  compare the first N stages, 2..5 (default: 5)

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

if [[ ! "$STAGE_COUNT" =~ ^[2-5]$ ]]; then
  echo "error: BOOTSTRAP_COMPARE_STAGE_COUNT must be an integer from 2 through 5" >&2
  exit 2
fi
for ((idx = 0; idx < STAGE_COUNT; idx++)); do
  stages+=("${all_stages[$idx]}")
done

if [[ ! -d "$STAGE_DIR" ]]; then
  echo "error: stage dir not found: $STAGE_DIR" >&2
  exit 2
fi
if [[ ! -f "$CORPUS" ]]; then
  echo "error: corpus not found: $CORPUS" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

STAGE_MANIFEST="$STAGE_DIR/bootstrap_stages.manifest"
if [[ ! -s "$STAGE_MANIFEST" ]]; then
  echo "error: stage provenance manifest missing: $STAGE_MANIFEST" >&2
  exit 2
fi
if ! grep -q '^status=success$' "$STAGE_MANIFEST" ||
   ! grep -q '^source_hash_consistent=1$' "$STAGE_MANIFEST" ||
   ! grep -q '^stable_manifest_run_id=.' "$STAGE_MANIFEST"; then
  echo "error: stage provenance manifest is incomplete or unsuccessful: $STAGE_MANIFEST" >&2
  exit 2
fi

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$path" | awk '{print $1}'
  else
    return 1
  fi
}

LOCK_DIR="$OUT_DIR/.bootstrap-ir-compare.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "error: bootstrap IR comparison output is already in use: $OUT_DIR" >&2
  exit 1
fi
cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

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
  expected_hash="$(awk -F= -v key="${stage}_sha256" '$1 == key { print $2; exit }' "$STAGE_MANIFEST")"
  actual_hash="$(sha256_file "$compiler" || true)"
  if [[ -z "$expected_hash" || "$actual_hash" != "$expected_hash" ]]; then
    echo "error: stage hash does not match provenance manifest: stage=$stage" >&2
    exit 2
  fi
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
      echo "IR_SHAPE_DIFF: $base vs $stage ($kind)" >&2
      echo "diff: $OUT_DIR/$base-vs-$stage.$kind.diff" >&2
      exit 1
    fi
  done
done

echo "IR_SHAPE_EQ: ${stages[*]} ok corpus=$CORPUS out=$OUT_DIR scope=normalized_text"
