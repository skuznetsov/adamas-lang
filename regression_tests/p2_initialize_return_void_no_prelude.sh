#!/usr/bin/env bash
# No-prelude guard for registration-time initialize return typing.
# `initialize` semantically returns Void/Nil regardless of the body expression;
# registration must not eagerly infer the body's return type.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_initialize_return_void_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/initialize_return_void.cr"
OUT="$TMP_DIR/initialize_return_void"
LOG="$TMP_DIR/initialize_return_void.log"

cat >"$SRC" <<'CR'
class Object
end

class Box
  def initialize(x : Int32)
    helper(x)
  end

  def helper(x : Int32) : Bool
    true
  end
end

Box.new(1)
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 1024 \
  "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

if ! grep -Fq 'func @Box#initialize$Int32' "$OUT.hir"; then
  echo "p2 initialize return regression: missing typed initialize" >&2
  cat "$LOG" >&2
  cat "$OUT.hir" >&2
  exit 1
fi

if ! grep -Fq 'func @Box#initialize$Int32(%0: 33, %1: 4) -> 0' "$OUT.hir"; then
  echo "p2 initialize return regression: initialize return was not Void" >&2
  cat "$LOG" >&2
  cat "$OUT.hir" >&2
  exit 1
fi

echo "p2_initialize_return_void_no_prelude_ok"
