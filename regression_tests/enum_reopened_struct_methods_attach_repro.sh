#!/usr/bin/env bash
# Regression: instance methods defined in a `struct Enum` body were never
# attached to concrete enums. cli.cr registers enums before classes, so when
# each enum ran attach_enum_instance_methods there were no `Enum#...` defs yet;
# the class/struct registration path (unlike the module path) never re-attached.
# Calls on enum values then resolved to the shared `Enum#tn` body, where
# `@type` is Enum instead of the receiver's enum (tn returned 4, not 2/5).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum_reopened_struct_methods_attach_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/em.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

struct Enum
  def tn : Int32
    {{@type.name.stringify.size}}
  end
end

enum Op : UInt8
  Add
end

enum Color
  Red
  Green
end

code = 0
code |= 1 unless Op::Add.tn == 2
code |= 2 unless Color::Green.tn == 5
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/em.cr" --no-prelude -o "$WORK_DIR/em" >"$WORK_DIR/em.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/em.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/em" 5 512 >"$WORK_DIR/em.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/em.run.log"; then
  echo "FAIL: struct Enum instance methods not specialized per enum" >&2
  cat "$WORK_DIR/em.run.log" >&2
  exit 1
fi
echo "PASS: struct Enum instance methods are attached to each enum"
