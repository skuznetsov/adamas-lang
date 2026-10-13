#!/usr/bin/env bash
# A branch updating an enum with a bitwise operator must not widen it to
# Enum | UInt8 and then dispatch an enum method through the integer arm.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum_carrier_branch_merge.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/flags.cr" <<'CR'
enum MergeFlags : UInt8
  A = 1
  B = 2

  def present?(other : self) : Bool
    (self & other) == other
  end
end

def sweep(options : MergeFlags, remove : Bool) : Bool
  if remove
    options &= ~MergeFlags::A
  end
  options.present?(MergeFlags::B) &&
    (options.present?(MergeFlags::A) != remove)
end

exit 1 unless sweep(MergeFlags::A | MergeFlags::B, true)
exit 2 unless sweep(MergeFlags::A | MergeFlags::B, false)
exit 0
CR

cat >"$WORK_DIR/mixed.cr" <<'CR'
enum MixedFlags : UInt8
  A = 1
  B = 2

  def code : Int32
    17
  end
end

struct UInt8
  def code : Int32
    23
  end
end

def mixed(value : MixedFlags, enum_branch : Bool) : Int32
  unless enum_branch
    value = 1_u8
  end
  value.code
end

def nullable(present : Bool) : Bool
  value = present ? MixedFlags::A : nil
  value.nil?
end

exit 3 unless mixed(MixedFlags::A, true) == 17
exit 4 unless mixed(MixedFlags::A, false) == 23
exit 5 if nullable(true)
exit 6 unless nullable(false)
exit 0
CR

for case_name in flags mixed; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 8192 \
      "$WORK_DIR/$case_name.cr" --no-prelude -o "$WORK_DIR/$case_name" \
      >"$WORK_DIR/$case_name.build.log" 2>&1; then
    cat "$WORK_DIR/$case_name.build.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$case_name" 5 512 \
      >"$WORK_DIR/$case_name.run.log" 2>&1; then
    cat "$WORK_DIR/$case_name.run.log" >&2
    exit 1
  fi
done
echo enum_carrier_branch_merge_repro_ok
