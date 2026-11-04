#!/usr/bin/env bash
# An unannotated helper's result must be independent of its name inside yield.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-inline-yield-module.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat >"$work/name_prefix.cr" <<'CR'
lib LibC
  fun putchar(value : Int32) : Int32
end

class String
end

struct Payload(T)
  def initialize(@pointer : Pointer(T), @code : Int32)
  end

  def code : Int32
    @code
  end
end

module Formatter
  def self.emit(ptr : Pointer(UInt8), *args, &)
    yield Payload.new(ptr, 65)
    yield to_payload(args[0], ptr)
  end

  private def self.to_payload(value, ptr)
    case value
    in String
      Payload.new(ptr, 66)
    in Payload(UInt8)
      value
    in Pointer(UInt8)
      Payload.new(value, 67)
    end
  end
end

def write(value : Payload(UInt8)) : Nil
  LibC.putchar(value.code)
  nil
end

def drive
  byte = 0_u8
  Formatter.emit(pointerof(byte), "text") do |chunk|
    write(chunk)
  end
end

drive
CR
sed 's/to_payload/payload/g' "$work/name_prefix.cr" >"$work/plain_name.cr"
sed 's/Payload.new(ptr, 66)/ptr/' "$work/name_prefix.cr" >"$work/pointer_result.cr"
printf 'AB' >"$work/expected"

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
  if [[ "$fixture" == pointer_result ]]; then
    if [[ "$status" != 1 || -e "$output" ]] || ! grep -Fq 'Pointer(UInt8)' "$output.compile.log"; then
      cat "$output.compile.log" >&2
      return 1
    fi
    if [[ "$compiler" == crystal ]]; then
      grep -Fq "expected argument #1 to 'write'" "$output.compile.log"
    else
      grep -Fq 'no overload matches write for argument types (Pointer(UInt8))' "$output.compile.log"
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
    cmp "$work/expected" "$output.stdout"
  fi
  printf 'PASS[%s] %s\n' "$compiler" "$fixture"
}

for fixture in name_prefix plain_name pointer_result; do
  check crystal "$fixture"
  (unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO; check lazy "$fixture")
  (unset ADAMAS_EAGER_HIR; export ADAMAS_EAGER_MONO=1; check eager "$fixture")
done
