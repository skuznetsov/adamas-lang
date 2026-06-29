#!/usr/bin/env bash
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/multi_ref_union_truthy_narrowing.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
BUILD_OUT="$TMP_DIR/build.out"
BUILD_ERR="$TMP_DIR/build.err"
RUN_OUT="$TMP_DIR/run.out"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
class A
  getter id : UInt32

  def initialize(@id : UInt32)
  end
end

class B
  getter id : UInt32

  def initialize(@id : UInt32)
  end
end

def maybe(flag : Bool) : (A | B | Nil)
  flag ? A.new(11_u32) : nil
end

def accept(x : A | B)
  puts "RESULT=#{x.id}"
end

if (v = maybe(true))
  accept(v)
end
STDOUT.flush
CR

set +e
env DEBUG_CALL_LOOKUP=accept "$COMPILER" "$SRC" -o "$BIN" >"$BUILD_OUT" 2>"$BUILD_ERR"
build_status=$?
set -e

if [[ $build_status -ne 0 ]]; then
  echo "compile failed"
  echo "compiler: $COMPILER"
  echo "status: $build_status"
  echo "tmp_dir: $TMP_DIR"
  echo "--- stderr ---"
  cat "$BUILD_ERR"
  echo "--- stdout ---"
  cat "$BUILD_OUT"
  exit 2
fi

if grep -q "CALL_LOOKUP_MISS.*func=accept" "$BUILD_ERR"; then
  echo "reproduced: truthy narrowing kept Nil in a multi-reference union call argument"
  echo "tmp_dir: $TMP_DIR"
  grep "CALL_LOOKUP_.*accept" "$BUILD_ERR" || true
  exit 1
fi

./scripts/run_safe.sh "$BIN" 5 256 >"$RUN_OUT"
stdout_text="$(awk '/^=== STDOUT ===/{flag=1;next}/^=== STDERR ===/{flag=0}flag' "$RUN_OUT" | tr -d '\r')"
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT:/{flag=0}flag' "$RUN_OUT" | tr -d '\r')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stdout:"
printf '%s\n' "$stdout_text"

if [[ "$stderr_text" == *"STUB CALLED:"* ]]; then
  echo "runtime stub reached"
  cat "$RUN_OUT"
  exit 1
fi

if [[ "$stdout_text" != "RESULT=11" ]]; then
  echo "unexpected output"
  cat "$RUN_OUT"
  exit 1
fi

echo "ok: multi-reference union truthy narrowing removes Nil"
