#!/usr/bin/env bash
# Tuple case patterns must read each subject element at its declared width.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tuple-case-width.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == 1 ]]; then
    echo "kept_tmp=$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT
cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def classify(value : UInt64, precision : Int32) : Int32
  case {value, precision}
  when {0, 0} then 10
  when {0, 1} then 11
  when {1, 1} then 12
  else 13
  end
end

def reverse(value : UInt64) : Int32
  case {1, value}
  when {1, 0} then 20
  when {1, 1} then 21
  else 22
  end
end

def signed(value : Int64) : Int32
  case {value, 1}
  when {0, 1} then 30
  when {1, 1} then 31
  else 32
  end
end

wide = 2147483648_u64 + 2147483648_u64
LibC.exit(11) unless classify(0_u64, 0) == 10
LibC.exit(12) unless classify(1_u64, 1) == 12
LibC.exit(13) unless classify(wide, 1) == 13
LibC.exit(14) unless classify(wide + 1_u64, 1) == 13
LibC.exit(15) unless reverse(wide) == 22
LibC.exit(16) unless reverse(wide + 1_u64) == 22
LibC.exit(17) unless signed(-(2147483648_i64 + 2147483648_i64)) == 32
LibC.exit(18) unless signed(1_i64) == 31
LibC.exit(19) unless 4294967296_u64 == wide
LibC.exit(20) unless 4294967297_u64 == wide + 1_u64
LibC.exit(0)
CRYSTAL
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
  "$WORK_DIR/probe.cr" --no-prelude -o "$WORK_DIR/probe" \
  >"$WORK_DIR/compile.log" 2>&1 || { cat "$WORK_DIR/compile.log"; exit 1; }
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/probe" 5 512 \
  >"$WORK_DIR/run.log" 2>&1 || { cat "$WORK_DIR/run.log"; exit 1; }
echo "PASS: tuple case subject widths and small-value controls"
