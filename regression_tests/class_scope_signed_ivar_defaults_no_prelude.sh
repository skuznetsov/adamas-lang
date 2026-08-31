#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_signed_ivar_defaults.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "compiler not found: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat >"$SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class SignedDefaults
  @regular = -7
  @small = -7_i8
  @ratio = -1.5

  def status : Int32
    return 1 unless @regular + 7 == 0
    return 2 unless @small + 7_i8 == 0_i8
    return 3 unless @ratio == -1.5
    0
  end
end

LibC.exit(SignedDefaults.new.status)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
  "$SRC" --no-prelude -o "$BIN" >"$COMPILE_LOG" 2>&1; then
  tail -120 "$COMPILE_LOG" >&2
  exit 1
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 256 >"$RUN_LOG" 2>&1; then
  cat "$RUN_LOG" >&2
  exit 1
fi

grep -Eq '\[EXIT: 0\]' "$RUN_LOG"
echo "class_scope_signed_ivar_defaults_no_prelude_ok"
