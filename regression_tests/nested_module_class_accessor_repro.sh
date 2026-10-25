#!/usr/bin/env bash
# Class accessors (class_getter/class_setter/class_property) in a module
# nested in a class registered no `def self.*`: the nested-module member pass
# had no accessor arms, unlike a top-level module body. The 1.22.1 prelude
# hit it as "undefined method 'execution_contexts' for
# Fiber::ExecutionContext" (`protected class_getter execution_contexts = ...`
# in `class Fiber; module ExecutionContext`). Each case exits 42 under
# original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested-module-accessor.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/getter.cr" <<'CR'
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

macro class_getter(*names)
  {% for name in names %}
    {% if name.is_a?(Assign) %}
      {% var_name = name.target %}
      @@{{name}}
    {% else %}
      {% var_name = name.id %}
    {% end %}
    def self.{{var_name}}
      @@{{var_name}}
    end
  {% end %}
end

class Fib
  module EC
    class_getter count = 40
  end
end

LibC.exit(Fib::EC.count + 2)
CR

cat > "$WORK_DIR/property_setter.cr" <<'CR'
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

macro class_getter(*names)
  {% for name in names %}
    {% if name.is_a?(Assign) %}
      {% var_name = name.target %}
      @@{{name}}
    {% else %}
      {% var_name = name.id %}
    {% end %}
    def self.{{var_name}}
      @@{{var_name}}
    end
  {% end %}
end

macro class_setter(*names)
  {% for name in names %}
    {% if name.is_a?(Assign) %}
      {% var_name = name.target %}
      @@{{name}}
    {% else %}
      {% var_name = name.id %}
    {% end %}
    def self.{{var_name}}=(@@{{var_name}})
    end
  {% end %}
end

macro class_property(*names)
  {% for name in names %}
    {% if name.is_a?(Assign) %}
      {% var_name = name.target %}
      @@{{name}}
    {% else %}
      {% var_name = name.id %}
    {% end %}
    def self.{{var_name}}
      @@{{var_name}}
    end

    def self.{{var_name}}=(@@{{var_name}})
    end
  {% end %}
end

class Fib
  module EC
    class_property count = 40
    class_setter base = 2
  end
end

# The setter calls only need to resolve: each stores the value already held.
Fib::EC.count = 40
Fib::EC.base = 2
LibC.exit(Fib::EC.count + 2)
CR

cat > "$WORK_DIR/protected_reopen.cr" <<'CR'
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

macro class_getter(*names)
  {% for name in names %}
    {% if name.is_a?(Assign) %}
      {% var_name = name.target %}
      @@{{name}}
    {% else %}
      {% var_name = name.id %}
    {% end %}
    def self.{{var_name}}
      @@{{var_name}}
    end
  {% end %}
end

class Box(T)
  def initialize
    @n = 40
  end

  def n : Int32
    @n
  end
end

class Fib
  module EC
    protected class_getter list = Box(EC).new
  end
end

class Fib
  module EC
    class Par
      include EC

      def go : Int32
        EC.list.n + 2
      end
    end
  end
end

LibC.exit(Fib::EC::Par.new.go)
CR

CASES=(
  "getter:42"
  "property_setter:42"
  "protected_reopen:42"
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
  printf '%d nested module class accessor case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'nested module class accessor cases passed\n'
