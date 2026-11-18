#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
work="$(mktemp -d "${TMPDIR:-/tmp}/case-local-enum.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/program.cr" <<'CR'
lib LibC
  fun putchar(x : Int32) : Int32
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
enum Kind
  A
  B
end
enum Other
  A
end
class Token
  def initialize(kind : Kind)
    LibC.putchar(65 &+ kind.value)
  end
end

def build(k : Int32)
  kind = Kind::A
  case k
  when 1
    kind = Kind::B
  end
  Token.new(kind)
end

def different(k : Int32)
  kind = Kind::A
  case k
  when 1
    kind = Other::A
  when 2
    kind = 0
  end
  if kind.is_a?(Kind)
    LibC.putchar(75)
  elsif kind.is_a?(Other)
    LibC.putchar(79)
  else
    LibC.putchar(73)
  end
end

build(0)
build(1)
different(0)
different(1)
different(2)
LibC.putchar(10)
CR
printf 'ABKOI\n' > "$work/expected"

for tool in stock candidate; do
  if [[ "$tool" == stock ]]; then
    build=("$safe" "$stock" 120 4096 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 120 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$work/program.cr" -o "$work/test"
  "$safe" "$work/test" 8 512 > "$work/actual"
  cmp "$work/expected" "$work/actual"
  echo "$tool passed case-local enum controls"
done
