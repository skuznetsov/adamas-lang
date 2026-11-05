#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-exact-call-metaclass.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > common.cr <<'CR'
lib LibC
  fun putchar(c : Int32) : Int32
end

class Parser
  def parse(value, type : Int32.class)
    65
  end

  def parse(value, type : Int32)
    66
  end

  def forward(value, type)
    parse(value, type)
  end

  def marker(type : Int32.class)
    67_u8
  end

  def marker(type : Int32)
    68_i32
  end

  def forward_marker(type)
    marker(type)
  end
end
CR

cat > calls.cr <<'CR'
require "./common"

def consume(value : UInt8)
  LibC.putchar(67)
end

def consume(value : Int32)
  LibC.putchar(value)
end

parser = Parser.new
LibC.putchar(parser.parse("1", Int32))
LibC.putchar(parser.parse("1", 1))
LibC.putchar(parser.parse("2", Int32))
LibC.putchar(parser.forward("1", 1))
LibC.putchar(parser.forward("1", Int32))
LibC.putchar(parser.forward("2", 2))
consume(parser.forward_marker(Int32))
consume(parser.forward_marker(1))
consume(parser.forward_marker(Int32))
CR

build_original() {
  "$safe" "$original" 60 4096 build "$1.cr" --prelude=empty --single-module \
    --no-debug "${original_flags[@]}" -o "$1.original"
}

build_candidate() {
  "$safe" "$candidate" 60 4096 "$1.cr" --no-prelude --no-debug \
    --no-ast-cache --no-llvm-cache -o "$1.candidate"
}

build_original calls > calls.original.log 2>&1 || { cat calls.original.log >&2; exit 1; }
build_candidate calls > calls.candidate.log 2>&1 || { cat calls.candidate.log >&2; exit 1; }
"$safe" "$work/calls.original" 5 512 > calls.original.out
"$safe" "$work/calls.candidate" 5 512 > calls.candidate.out
printf ABABABCDC | diff -u - calls.original.out
diff -u calls.original.out calls.candidate.out

printf 'PASS exact call identity retains instance and metaclass argument kinds\n'
