#!/usr/bin/env bash
# Typing and lowering share one named macro expansion per source invocation.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
adamas="${1:-$root/bin/adamas}"
crystal="${2:-$(command -v crystal)}"
work="$(mktemp -d "${TMPDIR:-/tmp}/named-macro-yield.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/tmp" "$work/cache"
export TMPDIR="$work/tmp" CRYSTAL_CACHE_DIR="$work/cache"
export NAMED_YIELD_COUNTER="$work/effects"

cat > "$work/zero.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class SourceMacroInput
  def initialize(@value : Int32)
  end

  private macro emit_result(other)
    {{ `printf x >> "$NAMED_YIELD_COUNTER"` }}
    return yield if @value < 0
    {{ other }}
  end

  def calculate(&block)
    emit_result(@value)
  end
end

actual = SourceMacroInput.new(-1).calculate { 42 }
LibC.exit(actual == 42 ? 0 : 23)
CR

cat > "$work/typed.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class NamedYieldTypedInput(T)
  def initialize(@value : T)
  end

  private macro emit_result(value, *, widen)
    {{ `printf x >> "$NAMED_YIELD_COUNTER"` }}
    {% if widen %}
      converted = {{ value }}.to_i64
      yield converted
    {% else %}
      yield {{ value }}
    {% end %}
  end

  def calculate(&block)
    emit_result(@value, widen: false)
  end
end

def check(arg : Int32)
  arg &+ 1
end

def check(arg : Int64)
  arg &+ 2_i64
end

actual = NamedYieldTypedInput(Int32).new(40).calculate { |arg| check(arg) }
LibC.exit(actual == 41 ? 0 : 23)
CR

cat > "$work/distinct.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

macro counted
  {% ordinal = `printf x >> "$NAMED_YIELD_COUNTER"; wc -c < "$NAMED_YIELD_COUNTER"` %}
  yield {{ ordinal.strip.id }}_i32
end

def invoke(&block)
  counted
end

a = invoke { |n| n }
b = invoke { |n| n }
LibC.exit(a == 1 && b == 2 ? 0 : 13)
CR

cat > "$work/distinct_nested.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

macro counted
  {% ordinal = `printf x >> "$NAMED_YIELD_COUNTER"; wc -c < "$NAMED_YIELD_COUNTER"` %}
  yield {{ ordinal.strip.id }}_i32
end

def invoke(&block)
  counted
end

def wrap(&block)
  local = invoke { |n| n }
  yield local
end

a = wrap { |n| n }
b = wrap { |n| n }
LibC.exit(a == 1 && b == 2 ? 0 : 13)
CR

cat > "$work/distinct_generic.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

macro counted
  {% ordinal = `printf x >> "$NAMED_YIELD_COUNTER"; wc -c < "$NAMED_YIELD_COUNTER"` %}
  yield {{ ordinal.strip.id }}_i32
end

def invoke(&block)
  counted
end

def wrap(filler : T) forall T
  invoke { |n| n }
end

a = wrap(0_i32)
b = wrap(0_i64)
LibC.exit(a == 1 && b == 2 ? 0 : 13)
CR

cat > "$work/rejected.cr" <<'CR'
class NamedMacroReject
  private macro deliver
    {{ `printf x >> "$NAMED_YIELD_COUNTER"` }}
    yield 7_i32
  end

  def run(&block)
    deliver
  end
end

def requires_text(value : String)
  value
end

NamedMacroReject.new.run { |value| requires_text(value) }
CR

cat > "$work/rejected_expansion.cr" <<'CR'
class ExpandedMacroReject
  private macro deliver
    {{ `printf x >> "$NAMED_YIELD_COUNTER"` }}
    requires_text(7_i32)
    yield 7_i32
  end

  def requires_text(value : String)
    value
  end

  def run(&block)
    deliver
  end
end

ExpandedMacroReject.new.run { |value| value }
CR

run_case() {
  local case_name="$1" mode="$2" expected_count="$3"
  shift 3
  local compiler="$1"
  shift
  local status=0 pattern
  : > "$NAMED_YIELD_COUNTER"
  "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$@" \
    "$work/$case_name.cr" -o "$work/program" > "$work/build.log" 2>&1 || status=$?
  if [[ "$case_name" == rejected* ]]; then
    if [[ "$mode" == crystal ]]; then
      pattern="Error: expected argument .*requires_text.*String.*Int32"
    else
      pattern="error: no overload matches .*requires_text.*Int32"
    fi
    if [[ "$status" != 1 ]] || ! grep -Eq "$pattern" "$work/build.log"; then
      cat "$work/build.log" >&2
      return 1
    fi
  else
    if [[ "$status" != 0 ]]; then
      cat "$work/build.log" >&2
      return 1
    fi
    "$root/scripts/run_safe.sh" "$work/program" 5 512
  fi
  local actual_count
  actual_count="$(wc -c < "$NAMED_YIELD_COUNTER")"
  if (( actual_count != expected_count )); then
    echo "$mode/$case_name executed the macro $actual_count times (expected $expected_count)" >&2
    return 1
  fi
  echo "PASS[$mode/$case_name]"
}

for case_name in zero typed distinct distinct_nested distinct_generic rejected rejected_expansion; do
  count=1
  [[ "$case_name" != distinct* ]] || count=2
  run_case "$case_name" crystal "$count" "$crystal" build --prelude=empty
  (
    unset ADAMAS_DISABLE_INLINE_YIELD
    run_case "$case_name" default "$count" "$adamas" --no-prelude --no-ast-cache --no-llvm-cache
  )
  (
    export ADAMAS_DISABLE_INLINE_YIELD=1
    run_case "$case_name" raw "$count" "$adamas" --no-prelude --no-ast-cache --no-llvm-cache
  )
done
