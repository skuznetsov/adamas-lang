#!/usr/bin/env bash
# Loop predecessors must preserve the source enum independently of its carrier.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/enum-loop.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/valid.cr" <<'CR'
lib LibC
  fun putchar(x : Int32) : Int32
end

enum Mark
  A
  B
end
enum OtherMark
  A
end

def emit(mark : Mark)
  LibC.putchar(65 &+ mark.value)
end

def ordinary(count : Int32)
  mark = Mark::A
  while count > 0
    mark = Mark::B
    count = count &- 1
  end
  emit(mark)
end

def mixed(count : Int32)
  mark = Mark::B
  while count > 0
    mark = 66
    count = count &- 1
  end
  LibC.putchar(mark.is_a?(Mark) ? 69 : 73)
end

def continued(count : Int32)
  mark = 66
  while count > 0
    count = count &- 1
    mark = Mark::A
    next
  end
  LibC.putchar(mark.is_a?(Mark) ? 69 : 73)
end

def stopped(count : Int32)
  mark = Mark::A
  until count == 0
    mark = OtherMark::A
    break
  end
  LibC.putchar(mark.is_a?(Mark) ? 66 : 82)
end

ordinary(0)
ordinary(2)
mixed(0)
mixed(1)
continued(0)
continued(1)
stopped(0)
stopped(1)
LibC.putchar(10)
CR

cat > "$work/invalid.cr" <<'CR'
enum Mark
  A
end
def invalid(count : Int32) : Mark
  mark = Mark::A
  while count > 0
    mark = 1
    break
  end
  mark
end
invalid(1)
CR
printf 'ABEIIEBR\n' > "$work/expected"

for tool in stock candidate; do
  if [[ "$tool" == stock ]]; then
    build=("$safe" "$stock" 120 4096 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 120 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$work/valid.cr" -o "$work/program"
  "$safe" "$work/program" 8 512 > "$work/actual"
  cmp "$work/expected" "$work/actual"
  if "${build[@]}" "$work/invalid.cr" -o "$work/invalid" > "$work/reject.log" 2>&1; then
    echo "$tool accepted an integer loop edge as an enum return" >&2
    exit 1
  fi
  grep -E 'must return.*Mark.*returning.*Int32' "$work/reject.log"
  echo "$tool passed enum loop edge controls"
done
