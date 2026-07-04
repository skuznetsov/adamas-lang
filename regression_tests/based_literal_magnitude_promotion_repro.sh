#!/usr/bin/env bash
# Regression: suffix-less hex/binary/octal literals must promote by magnitude
# like decimal literals do (host: first of Int32/Int64/UInt64 that fits).
#
# The lexer inferred NumberKind::I32 unconditionally for based literals, so
# `0x100000000` truncated to 0 and `0xFFFFFFFF` to -1. In stage2 this made
# File.tempname's `Random.rand(0x100000000)` raise "Invalid bound for rand: 0"
# and knocked parallel LLVM emission into the sequential fallback.
# Decimal literals above Int64::MAX (UInt64 on host) had the same tail.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/based_literal_mag.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"

cat > "$SRC" <<'CR'
puts 0x100000000
puts 0xFFFFFFFF
puts 0xFFFFFFFFFFFFFFFF
puts 0x7FFFFFFF
puts 0b100000000000000000000000000000000
puts 0o40000000000
puts 18446744073709551615
puts 0xFF_FFFF_FFFF
puts 0xFFu8
puts 0x10_i64
CR

"$COMPILER" "$SRC" -o "$OUT" >"$LOG" 2>&1 || {
  echo "COMPILE FAILED"
  tail -20 "$LOG"
  exit 1
}

ACTUAL="$("$RUN_SAFE" "$OUT" 10 512 2>/dev/null | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
EXPECTED=$'4294967296\n4294967295\n18446744073709551615\n2147483647\n4294967296\n4294967296\n18446744073709551615\n1099511627775\n255\n16'

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "MISMATCH"
  echo "--- expected ---"
  echo "$EXPECTED"
  echo "--- actual ---"
  echo "$ACTUAL"
  exit 1
fi

echo "OK: based/decimal literal magnitude promotion matches host"
