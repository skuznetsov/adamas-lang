#!/usr/bin/env bash
# Concrete scalar instances cannot match unrelated generic families.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-scalar-nominal.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat >"$work/unrelated_generics.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

struct Pair(T)
  def initialize(@value : T)
  end
end

struct Option(T)
  def initialize(@value : T)
  end
end

struct Record
  def initialize(value : Pair | Option)
  end
end

def write_field(value)
  case value
  when Pair, Option
    Record.new(value)
    LibC.putchar(82)
  when Bool
    LibC.putchar(66)
  else
    LibC.putchar(88)
  end
end

write_field(true)
LibC.putchar(10)
CRYSTAL
printf 'B\n' >"$work/unrelated_generics.expected"

cat >"$work/related_values.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

struct Symbol
end

struct Pair(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end

alias IntPair = Pair(Int32)

def visit(value)
  case value
  when IntPair
    LibC.putchar(value.value)
  when Char
    LibC.putchar(67)
  when Symbol
    LibC.putchar(83)
  when Bool
    LibC.putchar(66)
  else
    LibC.putchar(88)
  end
end

def check_metaclass(value)
  if value.is_a?(Pair(Int32))
    LibC.putchar(88)
  else
    LibC.putchar(75)
  end
end

visit(Pair(Int32).new(80))
visit('a')
visit(:a)
visit(true)
check_metaclass(Bool)
LibC.putchar(10)
CRYSTAL
printf 'PCSBK\n' >"$work/related_values.expected"

cat >"$work/reachable_error.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

struct Pair(T)
  def initialize(@value : T)
  end
end

struct Option(T)
  def initialize(@value : T)
  end
end

struct Record
  def initialize(value : Pair(Int32) | Option(Int32))
  end
end

def write_field(value)
  case value
  when Pair, Option
    Record.new(value)
    LibC.putchar(82)
  when Bool
    Record.new(value)
    LibC.putchar(66)
  else
    LibC.putchar(88)
  end
end

write_field(true)
LibC.putchar(10)
CRYSTAL

check() {
  local mode="$1" fixture="$2" result=0
  local output="$work/$mode-$fixture"
  local command=()
  if [[ "$mode" == crystal ]]; then
    command=("$original" 30 3072 build --prelude=empty --single-module "${stock_link[@]}")
  else
    command=("$candidate" 30 3072 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "$safe" "${command[@]}" --no-debug "$work/$fixture.cr" -o "$output" >"$output.compile.log" 2>&1 || result=$?
  if [[ "$fixture" == reachable_error ]]; then
    if [[ "$result" != 1 || -e "$output" ]] || ! grep -Fq 'not Bool' "$output.compile.log"; then
      cat "$output.compile.log" >&2
      return 1
    fi
  else
    if [[ "$result" != 0 ]]; then
      cat "$output.compile.log" >&2
      return 1
    fi
    "$safe" "$output" 5 512 >"$output.stdout" 2>"$output.run.log" || {
      cat "$output.run.log" >&2
      return 1
    }
    cmp "$work/$fixture.expected" "$output.stdout"
  fi
  printf 'PASS[%s] %s\n' "$mode" "$fixture"
}

for fixture in unrelated_generics related_values reachable_error; do
  check crystal "$fixture"
  (unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO; check lazy "$fixture")
  (unset ADAMAS_EAGER_HIR; export ADAMAS_EAGER_MONO=1; check eager "$fixture")
done
