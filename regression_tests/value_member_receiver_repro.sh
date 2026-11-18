#!/usr/bin/env bash
# An integer only has a value method if its own source declares one.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/value-member-receiver.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/good.cr" <<'CR'
lib LibC
  fun putchar(c : Int32) : Int32
end

struct Pointer(T)
  @[Primitive(:pointer_get)]
  def value : T
  end
end

enum Answer : Int32
  Letter = 65
end

struct Int32
  def value
    LibC.putchar(75)
    'K'
  end
end

def character(value : Char)
end

def number(value : Int32)
  value
end

struct Cell(T)
  def initialize(@item : T)
  end

  def item : T
    @item
  end
end

def type_position(n : Int32)
  character(Cell(typeof(n.value)).new('T').item)
end

n = 66
type_position(n)
character(n.value)
LibC.putchar(number(Answer::Letter.value))
LibC.putchar(number(pointerof(n).value))
LibC.putchar(10)
CR
cat > "$work/bad.cr" <<'CR'
def read_value(n : Int32)
  n.value
end
read_value(1)
CR
printf 'KAB\n' > "$work/expected"

for tool in original candidate; do
  if [[ "$tool" == original ]]; then
    build=("$safe" "$original" 120 4096 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 120 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$work/good.cr" -o "$work/$tool"
  "$safe" "$work/$tool" 8 512 > "$work/stdout"
  cmp "$work/expected" "$work/stdout"
  status=0
  "${build[@]}" "$work/bad.cr" -o "$work/invalid" > "$work/error" 2>&1 || status=$?
  if [[ "$status" != 1 || -e "$work/invalid" ]] || ! grep -Eq "undefined method 'value' for (an instance of )?Int32" "$work/error"; then
    cat "$work/error" >&2
    exit 1
  fi
  echo "$tool passed custom, enum, pointer and missing value method checks"
done
