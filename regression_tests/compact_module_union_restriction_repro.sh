#!/usr/bin/env bash
# A forwarded compact union must match a source restriction one member at a time.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/compact-module-union.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1 ADAMAS_LLVM_CACHE=0
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/positive.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

module Item(T)
end

class Included
  include Item(Int32)
end

class Forwarder
  @value : Item(Int32)?

  def initialize(@value : Item(Int32)?)
  end

  def forward
    Receiver.accept(@value)
  end
end

struct Receiver
  def self.accept(value : Item(Int32)?) : Int32
    value ? 65 : 66
  end
end

LibC.putchar(Forwarder.new(Included.new).forward)
LibC.putchar(Forwarder.new(nil).forward)
LibC.putchar(10)
CRYSTAL
# Nil still matches in each negative case. The other member must be checked.
sed 's/Item(Int32)/Item(Int64)/g; s/accept(value : Item(Int64)?)/accept(value : Item(Int32)?)/' \
  "$work/positive.cr" > "$work/wrong_application.cr"
sed 's/include Item(Int32)/extend Item(Int32)/; s/@value : Item(Int32)?/@value : Included?/g' \
  "$work/positive.cr" > "$work/extend_only.cr"

printf 'AB\n' > "$work/expected"
for compiler in original candidate; do
  if [[ "$compiler" == original ]]; then
    build=("$safe" "$original" 100 4096 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 100 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$work/positive.cr" -o "$work/$compiler"
  "$safe" "$work/$compiler" 8 512 > "$work/stdout"
  cmp "$work/expected" "$work/stdout"
  for probe in wrong_application extend_only; do
    status=0
    "${build[@]}" "$work/$probe.cr" -o "$work/$compiler-$probe" > "$work/error" 2>&1 || status=$?
    if [[ "$status" != 1 || -e "$work/$compiler-$probe" ]] || ! rg -q 'Receiver([.:])accept' "$work/error"; then
      cat "$work/error" >&2
      exit 1
    fi
  done
done
echo 'PASS: compact nullable module restriction checks both members and keeps applied include semantics.'
