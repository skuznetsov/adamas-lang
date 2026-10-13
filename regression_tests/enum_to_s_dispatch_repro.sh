#!/usr/bin/env bash
# Regression: an enum literal lowered through its base-integer carrier must still
# dispatch `to_s` / `to_s(io)` to the enum (Enum#to_s), not to Int32#to_s.
# Roots: lower_member_access took the Int32 class_info path for the carrier, and
# lower_call cast enum receivers of any one-arg call (not just operators) to Int32.
# Exit code bits: 1 = enum to_s missed, 2 = enum to_s(io) missed, 4 = Int32#to_s(io) hit.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum_to_s_dispatch.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/x.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class Hits
  @@enum_to_s = 0
  @@enum_to_s_io = 0
  @@int_to_s_io = 0

  def self.enum_to_s; @@enum_to_s = @@enum_to_s | 1; end
  def self.enum_to_s_io; @@enum_to_s_io = @@enum_to_s_io | 1; end
  def self.int_to_s_io; @@int_to_s_io = @@int_to_s_io | 1; end
  def self.code
    c = 0
    c |= 1 unless @@enum_to_s == 1
    c |= 2 unless @@enum_to_s_io == 1
    c |= 4 unless @@int_to_s_io == 0
    c
  end
end

class Sink
  def <<(obj)
    obj.to_s(self)
    self
  end
end

struct Int32
  def to_s(io : Sink)
    Hits.int_to_s_io
  end
end

struct Enum
  def to_s
    Hits.enum_to_s
    "E"
  end

  def to_s(io : Sink)
    Hits.enum_to_s_io
  end
end

enum Op
  Add
  Mul
end

Op::Mul.to_s
Sink.new << Op::Mul
LibC.exit(Hits.code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 "$WORK_DIR/x.cr" --no-prelude -o "$WORK_DIR/x" > "$WORK_DIR/compile.log" 2>&1; then
  echo "FAIL: compile failed"
  tail -20 "$WORK_DIR/compile.log"
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/x" 5 512 > "$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "FAIL: enum to_s dispatched to the integer method"
  cat "$WORK_DIR/run.log"
  exit 1
fi
echo "PASS"
