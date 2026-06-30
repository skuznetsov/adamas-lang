#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/array-index-nilable.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
LOG="$TMP_DIR/repro.run"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
def show(label, idx : Int32?)
  if idx
    puts "#{label}=IDX:#{idx}"
  else
    puts "#{label}=NIL"
  end
end

a = ["foo"]
show("miss_obj", a.index("bar"))
show("hit_obj", a.index("foo"))
show("miss_block", a.index { |x| x == "bar" })
show("direct_nil", nil.as(Int32?))
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

expected=$'miss_obj=NIL\nhit_obj=IDX:0\nmiss_block=NIL\ndirect_nil=NIL'
if [[ $compile_rc -eq 0 && $run_rc -eq 0 && "$stdout" == "$expected" ]]; then
  echo "PASS: Array#index(value) preserves Nil | Int32 contract"
  exit 0
fi

echo "FAIL: Array#index(value) did not preserve Nil | Int32 contract"
exit 1
