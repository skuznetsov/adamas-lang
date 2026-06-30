#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/proc-nilable-union-arg.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
LOG="$TMP_DIR/repro.run"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
struct Wrap
  getter id : UInt32

  def initialize(@id : UInt32)
  end
end

cast = ->(actual_type : String, actual_type_ref : Wrap?, value : String, expected_type : String, expected_type_ref : Wrap?) do
  if expected_type == "void"
    "VOID"
  elsif actual_type == expected_type
    value
  elsif expected_type_ref
    "REF"
  else
    expected_type
  end
end

present : Wrap? = Wrap.new(7_u32)
missing : Wrap? = nil
puts cast.call("ptr", present, "VALUE", "ptr", missing)
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

if [[ $compile_rc -eq 0 && $run_rc -eq 0 && "$stdout" == "VALUE" ]]; then
  echo "PASS: heap Proc indirect calls preserve nilable union arguments"
  exit 0
fi

echo "FAIL: heap Proc indirect call did not preserve nilable union arguments"
exit 1
