#!/usr/bin/env bash
# The fixed HIR String ID still participates in source class relations.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-string-nominal.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat >"$work/container_case.cr" <<'CR'
lib LibC
  fun putchar(value : Int32) : Int32
end

class String
end

class Hash(K, V)
end

struct NamedTuple
end

def visit(value)
  case value
  when Hash, NamedTuple
    LibC.putchar(value[:code])
  when String
    LibC.putchar(65)
  end
end

visit("abc")
visit({code: 66})
CR
printf 'AB' >"$work/container_case.expected"

cat >"$work/string_hierarchy.cr" <<'CR'
lib LibC
  fun putchar(value : Int32) : Int32
end

abstract class Reference
end

module TextMarker
  def code : Int32
    66
  end
end

class String
  include TextMarker
end

class TextChild < String
  def initialize(@marker : Int32)
  end

  def marker : Int32
    @marker
  end
end

def ancestor(value)
  case value
  when Reference
    LibC.putchar(65)
  else
    LibC.putchar(88)
  end
end

def included(value)
  if value.is_a?(TextMarker)
    LibC.putchar(value.code)
  else
    LibC.putchar(88)
  end
end

def text(flag : Bool)
  flag ? TextChild.new(67) : "other"
end

def descendant(flag : Bool)
  value = text(flag)
  case value
  when TextChild
    LibC.putchar(value.marker)
  else
    LibC.putchar(68)
  end
end

ancestor("hi")
included("hi")
descendant(true)
descendant(false)
CR
printf 'ABCD' >"$work/string_hierarchy.expected"

cat >"$work/string_metaclass.cr" <<'CR'
lib LibC
  fun putchar(value : Int32) : Int32
end
abstract class Reference
end
class String
end
def test_guard(value)
  if value.is_a?(Reference)
    LibC.putchar(88)
  else
    LibC.putchar(65)
  end
end
def select_case(value)
  case value
  when Reference
    LibC.putchar(88)
  else
    LibC.putchar(66)
  end
end
test_guard(String)
select_case(String)
CR
printf 'AB' >"$work/string_metaclass.expected"

cat >"$work/reachable_error.cr" <<'CR'
class String
end

def visit(value)
  case value
  when String
    value.missing_method
  end
end

visit("abc")
CR

check() {
  local compiler="$1" fixture="$2" status=0
  local output="$work/$fixture.$compiler"
  local command=()
  if [[ "$compiler" == crystal ]]; then
    command=("$original" 60 4096 build --prelude=empty --no-color "${stock_link[@]}")
  else
    command=("$candidate" 60 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "$safe" "${command[@]}" --no-debug "$work/$fixture.cr" -o "$output" >"$output.compile.log" 2>&1 || status=$?
  if [[ "$fixture" == reachable_error ]]; then
    if [[ "$status" != 1 || -e "$output" ]] || ! grep -Fq "undefined method 'missing_method'" "$output.compile.log"; then
      cat "$output.compile.log" >&2
      return 1
    fi
  else
    if [[ "$status" != 0 ]]; then
      cat "$output.compile.log" >&2
      return 1
    fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$safe" "$output" 5 512 >"$output.stdout" 2>"$output.run.log" || {
      cat "$output.run.log" >&2
      return 1
    }
    cmp "$work/$fixture.expected" "$output.stdout"
  fi
  printf 'PASS[%s] %s\n' "$compiler" "$fixture"
}

for fixture in container_case string_hierarchy string_metaclass reachable_error; do
  check crystal "$fixture"
  (unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO; check lazy "$fixture")
  (unset ADAMAS_EAGER_HIR; export ADAMAS_EAGER_MONO=1; check eager "$fixture")
done
