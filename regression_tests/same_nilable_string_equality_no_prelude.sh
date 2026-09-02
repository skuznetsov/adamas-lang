#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d /tmp/adamas_same_nilable_string_eq.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def optional(present : Bool, value : String) : String | Nil
  if present
    value
  else
    nil
  end
end

def optional_int(present : Bool, value : Int32) : Int32 | Nil
  if present
    value
  else
    nil
  end
end

class Probe
  def ==(other : Probe) : Bool
    true
  end

  def !=(other : Probe) : Bool
    true
  end
end

def optional_probe(present : Bool, value : Probe) : Probe | Nil
  if present
    value
  else
    nil
  end
end

nil_left = optional(false, "left")
nil_right = optional(false, "right")
same_left = optional(true, "same")
same_right = optional(true, "same")
different_string = optional(true, "different")
nil_int_left = optional_int(false, 1)
nil_int_right = optional_int(false, 2)
same_int_left = optional_int(true, 7)
same_int_right = optional_int(true, 7)
different_int = optional_int(true, 8)
probe_left = optional_probe(true, Probe.new)
probe_right = optional_probe(true, Probe.new)

LibC.exit(1) unless nil_left == nil_right
LibC.exit(2) if nil_left != nil_right
LibC.exit(3) if nil_left == same_right
LibC.exit(4) unless nil_left != same_right
LibC.exit(5) if same_left == nil_right
LibC.exit(6) unless same_left != nil_right
LibC.exit(7) unless same_left == same_right
LibC.exit(8) if same_left != same_right
LibC.exit(9) if same_left == different_string
LibC.exit(10) unless same_left != different_string
LibC.exit(11) unless nil_left.==(nil_right)
LibC.exit(12) if nil_left.!=(nil_right)
LibC.exit(13) unless nil_int_left == nil_int_right
LibC.exit(14) if nil_int_left != nil_int_right
LibC.exit(15) unless same_int_left == same_int_right
LibC.exit(16) if same_int_left != same_int_right
LibC.exit(17) if same_int_left == different_int
LibC.exit(18) unless same_int_left != different_int
LibC.exit(19) unless probe_left == probe_right
LibC.exit(20) unless probe_left != probe_right
LibC.exit(21) unless probe_left.!=(probe_right)
LibC.exit(0)
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
  "$TMP_DIR/repro.cr" --no-prelude --emit hir -o "$TMP_DIR/repro" \
  >"$TMP_DIR/build.log" 2>&1

if ! grep -Fq '__adamas_string_eq' "$TMP_DIR/repro.hir"; then
  echo "same nilable String equality regression: missing payload equality intrinsic" >&2
  grep -n -E 'Object#==|Object#!=|string_eq' "$TMP_DIR/repro.hir" >&2 || true
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$TMP_DIR/repro" 5 512 \
  >"$TMP_DIR/run.log" 2>&1

echo "same_nilable_string_equality_no_prelude_ok"
