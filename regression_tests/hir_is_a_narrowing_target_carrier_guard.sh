#!/usr/bin/env bash
# Regression: is_a? branch-narrowing metadata must not be carried as
# Array(Tuple(String, TypeRef)). Produced compilers can corrupt tuple arrays
# carrying a reference plus a small value across recursive helper returns.
# Use a reference carrier instead.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
AST_TO_HIR="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hir_is_a_target_carrier.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! grep -Fq 'private class IsANarrowingTarget' "$AST_TO_HIR"; then
  echo "FAIL: IsANarrowingTarget reference carrier is missing" >&2
  exit 1
fi

if ! grep -Fq 'private def is_a_narrowing_targets(condition_id : ExprId) : Array(IsANarrowingTarget)' "$AST_TO_HIR"; then
  echo "FAIL: is_a_narrowing_targets must return Array(IsANarrowingTarget)" >&2
  exit 1
fi

if grep -Fq 'Array(Tuple(String, TypeRef))' "$AST_TO_HIR" ||
   grep -Fq '[] of Tuple(String, TypeRef)' "$AST_TO_HIR"; then
  echo "FAIL: is_a narrowing target carrier regressed to Array(Tuple(String, TypeRef))" >&2
  exit 1
fi

if ! grep -Fq 'left << right.unsafe_fetch(idx)' "$AST_TO_HIR"; then
  echo "FAIL: is_a target merge should copy reference-carrier entries with an explicit loop" >&2
  exit 1
fi

SRC="$TMP_DIR/class_carrier_repro.cr"
OUT="$TMP_DIR/class_carrier_repro"
LOG="$TMP_DIR/run.log"

cat >"$SRC" <<'CR'
struct TypeRef
  getter id : UInt32

  def initialize(@id : UInt32)
  end
end

class Target
  getter name : String
  getter type : TypeRef

  def initialize(@name : String, @type : TypeRef)
  end
end

def leaf : Array(Target)
  [Target.new("parser", TypeRef.new(2566_u32))]
end

def targets(depth : Int32) : Array(Target)
  if depth == 0
    leaf
  else
    right = targets(depth - 1)
    right
  end
end

result = targets(1)
puts "RESULT #{result[0].name} #{result[0].type.id}"
CR

"$COMPILER" "$SRC" -o "$OUT" >"$LOG" 2>&1
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >>"$LOG" 2>&1

if ! grep -Fq 'RESULT parser 2566' "$LOG"; then
  echo "FAIL: reference carrier reducer did not preserve name/type across recursive return" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

echo "hir_is_a_narrowing_target_carrier_guard_ok"
