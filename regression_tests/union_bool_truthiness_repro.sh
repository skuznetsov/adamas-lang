#!/usr/bin/env bash
# A tagged union's truthiness must inspect the Bool payload as well as its tag.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_bool_truthiness.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

SOURCE="$WORK_DIR/repro.cr"
BIN="$WORK_DIR/repro"
BUILD_LOG="$WORK_DIR/build.log"
RUN_LOG="$WORK_DIR/run.log"

cat >"$SOURCE" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

# Keep all four values in one union so a branch must distinguish Nil and
# Bool(false), while retaining Int32(0) as a truthy non-Bool value.
def mixed(which : Int32) : Bool | Int32 | Nil
  if which == 0
    nil
  elsif which == 1
    false
  elsif which == 2
    true
  else
    0
  end
end

def nullable_bool(which : Int32) : Bool?
  if which == 0
    nil
  elsif which == 1
    false
  else
    true
  end
end

def branch_truth(value : Bool?) : Int32
  if value
    1
  else
    0
  end
end

def ternary_truth(value : Bool?) : Int32
  value ? 1 : 0
end

def not_truth(value : Bool?) : Int32
  if !value
    1
  else
    0
  end
end

def mixed_branch_truth(value : Bool | Int32 | Nil) : Int32
  if value
    1
  else
    0
  end
end

def mixed_not_truth(value : Bool | Int32 | Nil) : Int32
  if !value
    1
  else
    0
  end
end

# A user type may legally end in "Bool". Its false field and zero field do
# not make the object itself falsy, and it must not be parsed as primitive Bool
# by the descriptor-free backend fallback.
module BoolNameProbe
  class Bool
    def initialize(@flag : ::Bool, @zero : Int32)
    end
  end
end

def named_bool(which : Int32) : BoolNameProbe::Bool | Nil
  if which == 0
    nil
  else
    BoolNameProbe::Bool.new(false, 0)
  end
end

def named_bool_truth(value : BoolNameProbe::Bool | Nil) : Int32
  if value
    1
  else
    0
  end
end

# This guard runs before the known Bool(false) ternary failure, so it remains
# independently visible against an older compiler.
LibC.exit(61) unless named_bool_truth(named_bool(0)) == 0
LibC.exit(62) unless named_bool_truth(named_bool(1)) == 1

# The branch form must reject both Nil and Bool(false).
LibC.exit(11) unless branch_truth(nullable_bool(0)) == 0
LibC.exit(12) unless branch_truth(nullable_bool(1)) == 0
LibC.exit(13) unless branch_truth(nullable_bool(2)) == 1

# The ternary uses the same union condition lowering and catches the original
# regression directly.
LibC.exit(21) unless ternary_truth(nullable_bool(0)) == 0
LibC.exit(22) unless ternary_truth(nullable_bool(1)) == 0
LibC.exit(23) unless ternary_truth(nullable_bool(2)) == 1

# Negation must agree with the branch condition for all nullable Bool values.
LibC.exit(31) unless not_truth(nullable_bool(0)) == 1
LibC.exit(32) unless not_truth(nullable_bool(1)) == 1
LibC.exit(33) unless not_truth(nullable_bool(2)) == 0

# A non-Bool union member remains truthy even when its numeric value is zero.
LibC.exit(41) unless mixed_branch_truth(mixed(0)) == 0
LibC.exit(42) unless mixed_branch_truth(mixed(1)) == 0
LibC.exit(43) unless mixed_branch_truth(mixed(2)) == 1
LibC.exit(44) unless mixed_branch_truth(mixed(3)) == 1
LibC.exit(51) unless mixed_not_truth(mixed(0)) == 1
LibC.exit(52) unless mixed_not_truth(mixed(1)) == 1
LibC.exit(53) unless mixed_not_truth(mixed(2)) == 0
LibC.exit(54) unless mixed_not_truth(mixed(3)) == 0

LibC.exit(0)
CRYSTAL

if ! "$RUN_SAFE" "$COMPILER" 90 4096 "$SOURCE" --no-prelude -o "$BIN" >"$BUILD_LOG" 2>&1; then
  echo "FAIL: Bool-union truthiness repro did not compile" >&2
  cat "$BUILD_LOG" >&2
  exit 1
fi

set +e
"$RUN_SAFE" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  echo "FAIL: Bool-union truthiness (expected runtime status 0, got $run_status)" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "union_bool_truthiness_repro_ok"
