#!/usr/bin/env bash
# `getter!`/`property!` define a `name?` query returning `T?` and a `name`
# getter that raises NilAssertionError on nil. The parser turned them into the
# lightweight accessor nodes, which carry no bang semantics: the `!` was
# dropped, so `name` returned the raw nilable ivar and `name?` did not exist.
# Prelude hello failed with "undefined method 'index' for Nil" at
# crystal/event_loop/polling/arena.cr (`getter! index : Arena::Index?`), and a
# nil ivar read silently yielded 0. They now expand through Object's macros
# (copied verbatim from src/stdlib/object/properties.cr). The query stays
# nilable, so passing it to an Int32 parameter is rejected. Positive cases exit
# 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/getter-bang-macro.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  cat > "$WORK_DIR/$name.cr" <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class NilAssertionError
  def initialize(@message : String)
  end
end

def raise(e : NilAssertionError) : NoReturn
  LibC.exit(42)
end

class Object
  macro getter!(*names)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        @{{name}}?
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}}? {% if type %} : {{type}}? {% end %}
        @{{var_name}}
      end

      def {{var_name}} {% if type %} : {{type}} {% end %}
        if (%value = @{{var_name}}).nil?
          ::raise ::NilAssertionError.new("{{@type.id}}{{"#".id}}{{var_name}} cannot be nil")
        else
          %value
        end
      end

    {% end %}
  end

  macro property!(*names)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        @{{name}}?
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}}? {% if type %} : {{type}}? {% end %}
        @{{var_name}}
      end

      def {{var_name}} {% if type %} : {{type}} {% end %}
        if (%value = @{{var_name}}).nil?
          ::raise ::NilAssertionError.new("{{@type.id}}{{"#".id}}{{var_name}} cannot be nil")
        else
          %value
        end
      end

      def {{var_name}}=(@{{var_name}}{% if type %} : {{type}} {% end %})
      end

    {% end %}
  end
end

class Box
  getter! v : Int32

  def initialize(@v : Int32?)
  end
end

class PBox
  property! v : Int32

  def initialize(@v : Int32?)
  end
end

def take(x : Int32) : Int32
  x
end
HEAD
  printf '\n%s\n' "$body" >> "$WORK_DIR/$name.cr"
}

write_case getter_value_and_query 'a = Box.new(40)
b = Box.new(nil)
q = b.v? ? 100 : 2
LibC.exit(take(a.v) &+ q)'
write_case getter_nil_raises 'LibC.exit(take(Box.new(nil).v) &+ 1)'
write_case property_setter 'p = PBox.new(nil)
p.v = 41
LibC.exit(take(p.v) &+ 1)'
write_case property_nil_raises 'LibC.exit(take(PBox.new(nil).v) &+ 1)'
# Negative: the query keeps the nilable type.
write_case query_nilable_rejected 'LibC.exit(take(Box.new(42).v?))'

POSITIVE=(getter_value_and_query getter_nil_raises property_setter property_nil_raises)
NEGATIVE=(query_nilable_rejected)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${POSITIVE[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "42" ]]; then
      printf 'ORACLE FAIL: original %s did not exit 42\n' "$name" >&2
      exit 2
    fi
  done
  for name in "${NEGATIVE[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${POSITIVE[@]}"; do
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
  if [[ "$(exit_code_of "$run_log")" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run exit %s)\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" == "0" ]]; then
    printf 'FAIL %s (accepted)\n' "$name"
    failures=$((failures + 1))
  else
    printf 'PASS %s (rejected)\n' "$name"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
