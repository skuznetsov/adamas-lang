#!/usr/bin/env bash
# Guard default expansion for splat methods with post-splat named-only params.
#
# A positional call must not match an overload with a required named-only
# post-splat param. If it does, default expansion leaves the scalar arg
# unpacked and lowering materializes collect$Int32 instead of the tuple-shaped
# collect$Tuple(Int32)_Int32 target.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_splat_default_args_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/splat_default_args.cr"
OUT="$TMP_DIR/splat_default_args"
LOG="$TMP_DIR/compile.log"
MIR="$OUT.mir"

cat >"$SRC" <<'CR'
def collect(*values : Int32, required : Bool, scale = 10)
  values
end

def collect(*values : Int32, scale = 10)
  values
end

collect(5)
CR

CRYSTAL_V2_STOP_AFTER_MIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 1024 \
  "$SRC" --no-prelude --emit mir --no-link -o "$OUT" >"$LOG" 2>&1

if [[ ! -s "$MIR" ]]; then
  echo "p2_splat_default_args_no_prelude_failed: missing MIR artifact" >&2
  cat "$LOG" >&2
  exit 1
fi

if grep -Eq '^func @collect\$Int32\(' "$MIR"; then
  echo "p2_splat_default_args_no_prelude_failed: scalar splat wrapper emitted" >&2
  grep -En '^func @collect' "$MIR" >&2 || true
  exit 1
fi

if ! grep -Eq '^func @collect\$Tuple\(Int32\)_Int32\(' "$MIR"; then
  echo "p2_splat_default_args_no_prelude_failed: tuple splat wrapper missing" >&2
  grep -En '^func @collect' "$MIR" >&2 || true
  exit 1
fi

echo "p2_splat_default_args_no_prelude_ok"
