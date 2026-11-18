#!/usr/bin/env bash
# An ordinary source parameter restricted to Pointer(T) accepts a pointer.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/source-pointer-restriction.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/types.cr" <<'CR'
lib LibC
  fun putchar(c : Int32) : Int32
end

struct Pointer(T)
  @[Primitive(:pointer_get)]
  def value : T
  end
end

struct View(T)
  def initialize(@buffer : Pointer(T))
  end

  def first : T
    @buffer.value
  end
end
struct Pick(T)
  def initialize(value : Int32)
    @letter = 73
  end

  def initialize(value : Pointer(T))
    @letter = 80
  end

  def letter : Int32
    @letter
  end
end

alias Address = Pointer(Int32)
struct AliasView
  def initialize(@buffer : Address)
  end
  def first : Int32
    @buffer.value
  end
end

CR
cat > "$work/good.cr" <<'CR'
require "./types"
number = 65
address = pointerof(number)
LibC.putchar(View(Int32).new(address).first)
LibC.putchar(View(Pointer(Int32)).new(pointerof(address)).first.value)
LibC.putchar(AliasView.new(address).first)
LibC.putchar(Pick(Int32).new(number).letter)
LibC.putchar(Pick(Int32).new(address).letter)
LibC.putchar(10)
CR
printf 'AAAIP\n' > "$work/expected"
cat > "$work/computed.cr" <<'CR'
require "./types"
def ordinal : Int32
  17
end
View(Int32).new(ordinal)
CR
printf '%s\n' 'require "./types"' 'View(Int32).new(17)' > "$work/literal.cr"
printf '%s\n' 'require "./types"' 'View(Int32).new(false)' > "$work/bool.cr"
printf '%s\n' 'require "./types"' 'AliasView.new(17)' > "$work/aliased.cr"

for tool in original candidate; do
  if [[ "$tool" == original ]]; then
    build=("$safe" "$original" 120 4096 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 120 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$work/good.cr" -o "$work/$tool"
  "$safe" "$work/$tool" 8 512 > "$work/stdout"
  cmp "$work/expected" "$work/stdout"
  for probe in literal computed bool aliased; do
    actual=Int32
    if [[ "$probe" == bool ]]; then actual=Bool; fi
    status=0
    "${build[@]}" "$work/$probe.cr" -o "$work/$tool-$probe" > "$work/error" 2>&1 || status=$?
    if [[ "$status" != 1 || -e "$work/$tool-$probe" ]] || ! grep -Eq "(Pointer|Address).*not $actual" "$work/error"; then
      cat "$work/error" >&2
      exit 1
    fi
  done
  echo "$tool passed pointer restrictions, aliases and overload selection"
done
