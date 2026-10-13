#!/usr/bin/env bash
# Regression: constants produced by a class-body macro expansion.
# `register_class_members_from_expansion` had no ConstantNode/AssignNode arm,
# so `A = 7` inside a class-body `{% if %}` branch (or emitted by a macro call
# in the class body) was silently dropped; the use site then lowered `A` to an
# undefined local (value 0). Stdlib relies on this shape, e.g. string.cr
# `{% if compare_versions(Crystal::VERSION, "1.16.0") >= 0 %} CHAR_TO_DIGIT = ...`.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/class_body_macro_expansion_constant_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/mc.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
  fun strlen(p : UInt8*) : UInt64
end

macro mk_const
  B = 5
end

class Foo
  {% if true %}
    A = 7
  {% else %}
    A = 9
  {% end %}

  {% if 1 >= 0 %}
    S = "abc"
  {% end %}

  mk_const

  def self.a; A; end
  def self.b; B; end
  def self.s; S; end
end

code = 0
code |= 1 unless Foo.a == 7
code |= 2 unless Foo.b == 5
code |= 4 unless LibC.strlen(Foo.s.to_unsafe) == 3
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/mc.cr" --no-prelude -o "$WORK_DIR/mc" >"$WORK_DIR/mc.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/mc.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/mc" 5 512 >"$WORK_DIR/mc.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/mc.run.log"; then
  echo "FAIL: class-body macro-expansion constants not registered" >&2
  cat "$WORK_DIR/mc.run.log" >&2
  exit 1
fi
echo "PASS: class-body macro-expansion constants are registered"
