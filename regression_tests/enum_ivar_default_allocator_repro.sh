#!/usr/bin/env bash
# Regression: enum-typed ivar defaults (`@lifetime : Lt = Lt::Heap`) were stored
# as a pointer to a fresh zero struct. HIR registers enums as TypeKind::Struct,
# so generate_allocator / generate_allocator_overload took the struct-ivar path:
# the resolved scalar literal was discarded and `allocate (struct)` was stored
# instead (the field read back as garbage, not 3). Enums are integer value
# types; their defaults must be stored as plain literals.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum_ivar_default_allocator_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/ed.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

enum Lt : UInt8
  Unknown = 0
  StackLocal = 1
  Heap = 3
end

enum Color
  Red
  Green
  Blue
end

abstract class V
  @lifetime : Lt = Lt::Heap
  @k : UInt8 = 7_u8

  def lifetime; @lifetime; end
  def k; @k; end

  def initialize(@id : Int32); end
end

class Cp < V
  def initialize(id : Int32, @src : Int32)
    super(id)
  end
end

class Pl < V
end

class Paint
  @color : Color = Color::Blue
  def color; @color; end
end

c = Cp.new(1, 2)
p = Pl.new(4)
code = 0
code |= 1 unless c.lifetime.value == 3_u8
code |= 2 unless c.k == 7_u8
code |= 4 unless p.lifetime.value == 3_u8
code |= 8 unless p.k == 7_u8
code |= 16 unless Paint.new.color.value == 2
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/ed.cr" --no-prelude -o "$WORK_DIR/ed" >"$WORK_DIR/ed.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/ed.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/ed" 5 512 >"$WORK_DIR/ed.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/ed.run.log"; then
  echo "FAIL: enum ivar default not stored as its literal value" >&2
  cat "$WORK_DIR/ed.run.log" >&2
  exit 1
fi
echo "PASS: enum ivar defaults are stored as scalar literals"
