#!/usr/bin/env bash
set -euo pipefail

# B5 self-build frontier reducer (2026-07-03).
#
# A produced stage-2 compiler (cv2_s2) segfaults (exit 139) while COMPILING
# an ivar-array `each_with_index do |x, i| ... end` inside an instance method.
# Native stack: lower_call -> inline_yield_function(..., Nil|UInt32,
# Array(UInt32), BlockNode, Nil|Array(TypeRef), AstArena|PageArena|VirtualArena)
# -> lower_body -> garbage node dispatch (lower_super null deref, or
# NodeSlot#node null self via the AstArena#[] vdispatch on the full
# src/adamas.cr self-build). Suspected root family: TODO(s2b-union-arg-abi)
# call-ABI slot misplacement for nilable/union args emitted by stage1's
# llvm_backend (see docs/compiler_architecture_sdd.md section 0 and
# LANDMARKS.md).
#
# Usage:
#   regression_tests/b5_selfhost_each_with_index_inline_yield_repro.sh <cv2_s2>
#
# Green (fixed): the stage-2 compiler compiles the reducer with exit 0.
# Measured-red assertion of the known frontier:
#   ADAMAS_EXPECT_B5_EWI_CRASH=1 regression_tests/b5_selfhost_each_with_index_inline_yield_repro.sh <cv2_s2>

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE2="${1:?usage: $0 <stage2-compiler>}"

TMP_DIR="$(mktemp -d /tmp/b5_ewi_repro.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/reducer.cr" <<'CR'
class Runner
  @args : Array(String) = [] of String

  def initialize(args : Array(String))
    @args = args
  end

  def run
    @args.each_with_index do |arg, i|
      STDERR.puts "arg[#{i}]=#{arg.bytesize}b '#{arg}'"
      STDERR.flush
    end
  end
end

Runner.new(["a", "bb"]).run
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$STAGE2" 120 12288 \
  "$TMP_DIR/reducer.cr" -o "$TMP_DIR/reducer_bin" > "$TMP_DIR/compile.log" 2>&1
rc=$?
set -e

if [[ "${ADAMAS_EXPECT_B5_EWI_CRASH:-0}" == "1" ]]; then
  if [[ "$rc" -eq 0 ]]; then
    echo "UNEXPECTED-GREEN: stage2 compiled the each_with_index reducer; drop ADAMAS_EXPECT_B5_EWI_CRASH"
    exit 1
  fi
  echo "measured-red as expected: stage2 compile rc=$rc"
  tail -3 "$TMP_DIR/compile.log" || true
  exit 0
fi

if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: stage2 compile of each_with_index reducer rc=$rc (B5 frontier still red)"
  tail -5 "$TMP_DIR/compile.log" || true
  exit 1
fi

echo "OK: stage2 compiled the each_with_index reducer"
exit 0
