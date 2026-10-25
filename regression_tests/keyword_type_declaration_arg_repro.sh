#!/usr/bin/env bash
# A command-call argument `when : Int64` (keyword name, ` : `, type) is a
# TypeDeclaration, as in 1.22.1's
#   record ZoneTransition, when : Int64, index : UInt8, standard : Bool, utc : Bool
# (time/location.cr). The keyword arm of parse_prefix required a whitespace
# token before the colon, which the default lexer mode never emits, so
# `when : Int64` became the identifier `when` plus a named argument. Macro
# argument reparse (macro defined in another file) then rejected the record
# call and ZoneTransition had no methods: "undefined method 'index' for
# Time::Location::ZoneTransition". A keyword first argument also ended the
# command call (`show when : Int64` -> undefined method 'when').
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/keyword-type-decl-arg.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

struct UInt8
  @[Primitive(:convert)]
  def to_i : Int32
  end
end

macro show(*properties)
  {% for property in properties %}
    {% raise "not a TypeDeclaration" unless property.is_a?(TypeDeclaration) %}
  {% end %}
  LibC.exit({{properties.size}} + 39)
end
CR

# Defined in a separate file so the call's arguments are reparsed into the
# macro's arena, as for the prelude's `record`.
cat > "$WORK_DIR/rec_macro.cr" <<'CR'
macro getter(*names)
  {% for name in names %}
    @{{name.var.id}} : {{name.type}}
    def {{name.var.id}} : {{name.type}}
      @{{name.var.id}}
    end
  {% end %}
end

macro record(name, *properties)
  struct {{name.id}}
    {% for property in properties %}
      getter {{property.var.id}} : {{property.type}}
    {% end %}
    def initialize({{ properties.map { |field| "@#{field.var.id}".id }.splat }})
    end
  end
end
CR

{ cat "$WORK_DIR/header.cr"; echo 'show when : Int64, index : UInt8, std : Bool'; } > "$WORK_DIR/first_arg.cr"
{ cat "$WORK_DIR/header.cr"; echo 'show index : UInt8, when : Int64, std : Bool'; } > "$WORK_DIR/later_arg.cr"
{ cat "$WORK_DIR/header.cr"; echo 'show else : Int64, then : Int32, rescue : Bool'; } > "$WORK_DIR/other_keywords.cr"
{ cat "$WORK_DIR/header.cr"; cat <<'CR'; } > "$WORK_DIR/record_reparse.cr"
require "./rec_macro"

record ZT, when : Int64, index : UInt8, std : Bool

z = ZT.new(5_i64, 37_u8, true)
LibC.exit(z.index.to_i + 5)
CR

CASES=(
  "first_arg:42"
  "later_arg:42"
  "other_keywords:42"
  "record_reparse:42"
)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d keyword type declaration argument case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'keyword type declaration argument cases passed\n'
