#!/usr/bin/env bash
# Regression: named-only overload filtering must apply only to the RAW callsite
# shape. The allocator (`.new` -> initialize) and full-shape acceptance checks
# pass a normalized argument list where named args are already folded into
# positional slots. Capping that list at the positional prefix rejected every
# overload, the fallback picked `initialize(lexer, *, recovery_mode)`, and the
# second positional (an Arena) was coerced to the Bool named-only param.
# Bootstrap impact: stage 2 built `Parser.new(lexer, arena, recovery_mode: true)`
# with the wrong initializer and segfaulted in extract_enum_member_from_parsed_expr.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named_only_allocator_normalized_args_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/p.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Arena
  def initialize(@n : Int32)
  end
  def n
    @n
  end
end
class P
  @arena : Arena
  @rm : Bool
  def initialize(lexer : Int32, *, recovery_mode : Bool = false)
    @arena = Arena.new(1)
    @rm = recovery_mode
  end
  def initialize(lexer : Int32, @arena : Arena, *, recovery_mode : Bool = false, depth : Int32 = 0)
    @rm = recovery_mode
  end
  def code
    @arena.n + (@rm ? 100 : 0)
  end
end
a = Arena.new(42)
p = P.new(7, a, recovery_mode: true)
LibC.exit(p.code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/p.cr" --no-prelude -o "$WORK_DIR/p" >"$WORK_DIR/p.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/p.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/p" 5 512 >"$WORK_DIR/p.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 142\]' "$WORK_DIR/p.run.log"; then
  echo "FAIL: allocator picked the named-only initialize overload (expected exit 142)" >&2
  cat "$WORK_DIR/p.run.log" >&2
  exit 1
fi
echo "PASS: allocator resolves initialize overloads from the raw callsite shape"
