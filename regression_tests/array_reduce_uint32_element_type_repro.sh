#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/array-reduce-uint32.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
LOG="$TMP_DIR/repro.run"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
def show(label, value : UInt32)
  puts "#{label}=#{value}"
end

vals = [1_u32, 2_u32, 3_u32]
plain = vals.reduce { |acc, x| acc + x }
show("plain", plain)
CR

set +e
"$COMPILER" "$SRC" -o "$BIN" >"$LOG.compile.out" 2>"$LOG.compile.err"
compile_rc=$?
if [[ $compile_rc -eq 0 ]]; then
  "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 256 >"$LOG"
  run_rc=$?
else
  run_rc=-1
fi
set -e

stdout=""
if [[ $run_rc -eq 0 ]]; then
  stdout="$(awk '/^=== STDOUT ===/{flag=1;next}/^=== STDERR ===/{flag=0}flag' "$LOG" 2>/dev/null | tr -d '\r')"
fi

echo "compiler: $COMPILER"
echo "compile_rc: $compile_rc"
echo "run_rc: $run_rc"
echo "stdout:"
printf '%s\n' "$stdout"

if [[ $compile_rc -eq 0 && $run_rc -eq 0 && "$stdout" == "plain=6" ]]; then
  echo "PASS: Array(UInt32)#reduce keeps UInt32 element/accumulator type"
  exit 0
fi

echo "FAIL: Array(UInt32)#reduce did not keep UInt32 element/accumulator type"
exit 1
