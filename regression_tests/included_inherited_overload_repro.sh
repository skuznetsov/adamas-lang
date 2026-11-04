#!/usr/bin/env bash
# An incompatible included overload does not hide a compatible class overload.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-inherited-overload.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

write_probe() {
  local input="$1" first="$2" second="$3" body="${4:-13}"
  cat <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Sink
end

class DerivedSink < Sink
end

class Wrong; end

class Builder
end

class Object
  def serialize(output : Sink) : Int32
    $body
  end
end

module Details
  def serialize(output : Builder) : Int32
    detail
  end
end

abstract class Resource
  include Details
  abstract def detail : Int32
end

class FirstResource < Resource
  include Details

  def detail : Int32
    11
  end
end

class SecondResource < Resource
  include Details

  def detail : Int32
    21
  end
end

CR
  sed -e "s/INPUT/$input/g" -e "s/EXPECTED_ONE/$first/g" -e "s/EXPECTED_TWO/$second/g" <<'CR'
class Writer
  def initialize(@resource : Resource)
  end

  private def with_resource(&)
    yield @resource
  end

  def run
    with_resource { |resource| resource.serialize(INPUT.new) }
  end
end

LibC.exit(1) unless Writer.new(FirstResource.new).run == EXPECTED_ONE
LibC.exit(2) unless Writer.new(SecondResource.new).run == EXPECTED_TWO
CR
}

check() {
  local compiler="$1" mode="$2" status=0
  local source="$work/$mode.cr" output="$work/$compiler.$mode"
  local command=()
  if [[ "$compiler" == crystal ]]; then
    command=("$original" 60 4096 build --prelude=empty --no-color "${stock_link[@]}")
  else
    command=("$candidate" 60 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi

  "$safe" "${command[@]}" --no-debug "$source" -o "$output" >"$output.compile.log" 2>&1 || status=$?
  if [[ "$mode" == rejected ]]; then
    if [[ "$status" != 1 ]] || ! grep -Eiq '^error: .*Resource#serialize' "$output.compile.log"; then
      cat "$output.compile.log" >&2
      return 1
    fi
  else
    if [[ "$status" != 0 ]]; then
      cat "$output.compile.log" >&2
      return 1
    fi
    "$safe" "$output" 5 512 >"$output.run.log" 2>&1 || {
      cat "$output.run.log" >&2
      return 1
    }
    grep -Fq '[EXIT: 0]' "$output.run.log"
  fi
  printf 'PASS[%s] %s\n' "$compiler" "$mode"
}

write_probe DerivedSink 13 13 >"$work/inherited.cr"
write_probe Builder 11 21 >"$work/included.cr"
write_probe Sink 13 23 'serialize(Builder.new) &+ 2' >"$work/redispatch.cr"
write_probe Wrong 0 0 >"$work/rejected.cr"
for mode in inherited included redispatch rejected; do
  check crystal "$mode"
  check adamas "$mode"
done
