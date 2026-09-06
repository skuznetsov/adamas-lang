#!/usr/bin/env bash
# Array#index must return the first equal value, not the first identical box.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array_index_equality.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct IndexKey
  getter id : UInt32
  def initialize(@id : UInt32)
  end
  def ==(other : IndexKey) : Bool
    @id == other.id
  end
  def ==(other : Int32) : Bool
    @id == other.to_u32
  end
end
keys = [IndexKey.new(1_u32), IndexKey.new(2_u32), IndexKey.new(2_u32)]
LibC.exit(21) unless keys.index(IndexKey.new(2_u32)) == 1
LibC.exit(22) unless keys.index(IndexKey.new(3_u32)).nil?
LibC.exit(23) unless ([] of IndexKey).index(IndexKey.new(1_u32)).nil?
# A user overload may intentionally compare different types.
LibC.exit(24) unless keys.index(2) == 1
LibC.exit(25) unless keys.index(3).nil?
LibC.exit(26) unless keys.includes?(2)
LibC.exit(27) if keys.includes?(3)
def name(prefix : String) : String
  prefix + "(String)"
end
names = [name("First"), name("Hash"), name("Hash")]
LibC.exit(31) unless names.index("Hash(String)") == 1
LibC.exit(32) unless names.index("Missing(String)").nil?
LibC.exit(33) unless ([] of String).index("Hash(String)").nil?
LibC.exit(41) unless [17, 23, 23].index(23) == 1
LibC.exit(42) unless [17, 23].index(19).nil?
LibC.exit(0)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo array_index_value_equality_repro_ok
