#!/usr/bin/env bash
# Replaying an eager module body must keep the pointer in its required formal.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/module-required-replay.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
export CRYSTAL_CACHE_DIR="$tmp/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$tmp/module.cr" <<'CR'
lib LibC
  fun memcmp(left : UInt8*, right : UInt8*, count : UInt64) : Int32
  fun putchar(code : Int32) : Int32
end

module ModuleReplay
  extend self

  def emit(path, mode = 66, follow = true)
    LibC.memcmp(path, path, 1_u64)
    LibC.putchar(follow ? mode : 65)
  end

  def keyword_only(*, path, mode = 66, follow = true)
    LibC.putchar(follow ? mode : path)
  end

  def relay(path, mode = 0)
    ModuleReplay.emit(path, 67, false)
  end
end
CR

cp "$tmp/module.cr" "$tmp/good.cr"
cat >> "$tmp/good.cr" <<'CR'
byte = 77_u8
ModuleReplay.relay(pointerof(byte))
ModuleReplay.emit(pointerof(byte))
ModuleReplay.emit(follow: true, mode: 67, path: pointerof(byte))
ModuleReplay.keyword_only(path: 75, follow: false)
LibC.putchar(10)
CR
cp "$tmp/module.cr" "$tmp/bad.cr"
echo 'ModuleReplay.emit(123, 67, false)' >> "$tmp/bad.cr"
printf 'ABCK\n' > "$tmp/expected"

for tool in crystal adamas; do
  if [[ "$tool" == crystal ]]; then
    compile=("$safe" "$original" 150 4096 build --prelude=empty "${link[@]}")
  else
    compile=("$safe" "$candidate" 150 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  if ! "${compile[@]}" "$tmp/good.cr" -o "$tmp/$tool" > "$tmp/compile.log" 2>&1; then
    cat "$tmp/compile.log" >&2
    exit 1
  fi
  "$safe" "$tmp/$tool" 10 512 > "$tmp/$tool.out"
  cmp "$tmp/expected" "$tmp/$tool.out"
  if "${compile[@]}" "$tmp/bad.cr" -o "$tmp/invalid" > "$tmp/invalid.log" 2>&1; then
    echo "$tool accepted an Int32 as the memcmp pointer" >&2
    exit 1
  fi
  if ! grep -iq 'memcmp' "$tmp/invalid.log" || ! grep -Eq 'Int32.*Pointer|Pointer.*Int32' "$tmp/invalid.log"; then
    cat "$tmp/invalid.log" >&2
    exit 1
  fi
  echo "$tool passed the positional, default, named-only and invalid pointer cases"
done
