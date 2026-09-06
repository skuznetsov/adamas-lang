#!/usr/bin/env bash
# Array membership must call a struct's value equality, not compare its boxes.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array_struct_membership.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct MembershipKey
  getter id : UInt32
  def initialize(@id : UInt32)
  end
  def ==(other : MembershipKey) : Bool
    @id == other.id
  end
end
keys = [MembershipKey.new(1_u32), MembershipKey.new(2_u32)]
LibC.exit(11) unless keys.includes?(MembershipKey.new(1_u32))
LibC.exit(12) if keys.includes?(MembershipKey.new(3_u32))
LibC.exit(13) if ([] of MembershipKey).includes?(MembershipKey.new(1_u32))
# Preserve scalar membership and retain false for a mismatching scalar.
LibC.exit(14) unless [1, 2].includes?(2)
LibC.exit(15) if [1, 2].includes?(3)
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
# Exercise the actual stdlib small-array uniq consumer with the same values.
sed '/^LibC.exit(0)$/d' "$WORK_DIR/repro.cr" >"$WORK_DIR/uniq.cr"
cat >>"$WORK_DIR/uniq.cr" <<'CR'
# The full prelude provides Struct#== for unrelated argument types.
LibC.exit(18) if keys.includes?(1)
unique = [MembershipKey.new(1_u32), MembershipKey.new(1_u32), MembershipKey.new(2_u32)].uniq
LibC.exit(16) unless unique.size == 2
LibC.exit(17) unless unique[0].id == 1_u32 && unique[1].id == 2_u32
LibC.exit(0)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 8192 \
    "$WORK_DIR/uniq.cr" -o "$WORK_DIR/uniq" >"$WORK_DIR/uniq-build.log" 2>&1; then
  cat "$WORK_DIR/uniq-build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/uniq" 5 512 >"$WORK_DIR/uniq-run.log" 2>&1; then
  cat "$WORK_DIR/uniq-run.log" >&2
  exit 1
fi
echo array_struct_value_membership_repro_ok
