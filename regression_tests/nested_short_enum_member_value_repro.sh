#!/usr/bin/env bash
# A single-letter nested type name (`enum P` inside `class Foo`) was treated as an
# unbound generic type parameter by resolve_path_string_in_context, so an unqualified
# `P::B` inside Foo missed the enum table and lowered to the literal 0.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested_short_enum_member_value_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Foo
  enum P
    A
    B
    C
  end
  enum Q2
    A
    B
  end
  def b : Int32
    x = P::B
    x.value
  end
  def c : Int32
    P::C.value
  end
  def q : Int32
    Q2::B.value
  end
end
LibC.exit(1) unless Foo.new.b == 1
LibC.exit(2) unless Foo.new.c == 2
LibC.exit(3) unless Foo.new.q == 1
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
echo nested_short_enum_member_value_repro_ok
