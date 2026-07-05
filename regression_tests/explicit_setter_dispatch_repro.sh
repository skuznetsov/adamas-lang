#!/usr/bin/env bash
# Oracle for explicit-setter dispatch (Char::Reader#pos= stale current_char,
# final layer of the Path#each_parent wrong-parents family).
#
# Crystal semantics: `obj.field = v` is always a call to `field=`. Two V2
# paths bypassed an explicit `def field=`:
#   1. lower_assign preferred the raw ivar FieldSet fast path whenever the
#      class had an ivar named @field, never checking for a real setter def.
#   2. ensure_accessor_method synthesized a bare ivar-store accessor under
#      the setter's mangled name, shadowing the not-yet-lowered real def.
# Char::Reader#pos= re-decodes current_char; both bypasses left the reader
# stale, so Path#each_part_separator_index consumed the wrong prefix and
# each_parent yielded "/a/" instead of "/", "/a", ...
#
# Synthesized property accessors register no DefNode and keep the FieldSet
# fast path (checked here via the class case too).
#
# RED (pre-fix): seen=0 for struct and class. GREEN: seen=1 for both.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/explicit_setter.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

run_case() {
  local kind="$1"
  local src="$TMP_DIR/repro_$kind.cr"
  local out="$TMP_DIR/repro_$kind"
  cat > "$src" <<CR
lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

$kind Box
  @x : Int32
  @seen : Int32

  def initialize
    @x = 0
    @seen = 0
  end

  def x=(v : Int32)
    @seen = @seen + 1
    @x = v
  end

  def x
    @x
  end

  def seen
    @seen
  end
end

b = Box.new
b.x = 42
LibC.printf("x=%d seen=%d\n", b.x, b.seen)
CR

  if ! "$COMPILER" "$src" --no-prelude -o "$out" > "$TMP_DIR/compile_$kind.log" 2>&1; then
    echo "FAIL($kind): compile error" >&2
    tail -5 "$TMP_DIR/compile_$kind.log" >&2
    return 1
  fi

  local raw got
  raw="$("$ROOT_DIR/scripts/run_safe.sh" "$out" 10 512 2>/dev/null)"
  got="$(echo "$raw" | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
  if [[ "$got" != "x=42 seen=1" ]]; then
    echo "FAIL($kind): explicit setter bypassed" >&2
    echo "--- expected: x=42 seen=1" >&2
    echo "--- got: $got" >&2
    return 1
  fi
  return 0
}

run_case "struct" || exit 1
run_case "class" || exit 1
echo "PASS: explicit setter defs dispatch as calls for struct and class"
