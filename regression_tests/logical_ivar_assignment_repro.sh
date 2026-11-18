#!/usr/bin/env bash
# Compare the storage and result of short-circuit field writes with Crystal.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal)}}"
adamas="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/logical-ivar.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
export RUN_SAFE_PASSTHROUGH_STDIO=1 CRYSTAL_CACHE_DIR="$tmp/cache"
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld -L/opt/homebrew/lib -lgc}"
fi

cat > "$tmp/common.cr" <<'CR'
lib LibC
  fun putchar(code : Int32) : Int32
end

class Job
  def initialize(@mark : Int32)
  end

  def mark
    @mark
  end
end

class Cache
  def fetch
    @job ||= begin
      LibC.putchar(73)
      mark = 65
      Job.new(mark)
    end
  end

  def peek
    @job
  end

  def boolean
    @flag ||= begin
      LibC.putchar(70)
      false
    end
  end

  def populate
    @choice ||= 65
  end

  def switch
    @choice = 'B'
  end

  def choose(flag : Bool)
    @choice = 'B'
    @choice = 66_u8 if flag
    @choice
  end
end

def mark(job : Job)
  LibC.putchar(job.mark)
end

def show(choice : Int32)
  LibC.putchar(choice)
end

def show(choice : Char)
  LibC.putchar(67)
end

def show(choice : UInt8)
  LibC.putchar(85)
end

def show(choice : Nil)
  LibC.putchar(78)
end
CR
cp "$tmp/common.cr" "$tmp/valid.cr"
cat >> "$tmp/valid.cr" <<'CR'
cache = Cache.new
LibC.putchar(cache.peek.nil? ? 78 : 88)
mark(cache.fetch)
mark(cache.fetch)
LibC.putchar(cache.peek.nil? ? 88 : 89)
LibC.putchar(cache.boolean ? 88 : 65)
LibC.putchar(cache.boolean ? 88 : 66)
show(cache.populate)
show(cache.switch)
show(cache.populate)
show(cache.choose(false))
show(cache.choose(true))
show(cache.populate)
LibC.putchar(10)
CR
cp "$tmp/common.cr" "$tmp/invalid.cr"
cat >> "$tmp/invalid.cr" <<'CR'
def accept_int(value : Int32)
  LibC.putchar(value)
end
accept_int(Cache.new.fetch)
CR
printf 'NIAAYFAFBACCCUU\n' > "$tmp/expected"
for compiler in crystal adamas; do
  if [[ "$compiler" == crystal ]]; then
    build=("$safe" "$stock" 150 4096 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$adamas" 150 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  if ! "${build[@]}" "$tmp/valid.cr" -o "$tmp/program" > "$tmp/build.log" 2>&1; then
    cat "$tmp/build.log" >&2
    exit 1
  fi
  "$safe" "$tmp/program" 10 512 > "$tmp/stdout"
  cmp "$tmp/expected" "$tmp/stdout"
  if "${build[@]}" "$tmp/invalid.cr" -o "$tmp/invalid" > "$tmp/reject.log" 2>&1; then
    echo "$compiler accepted a Job as an Int32" >&2
    exit 1
  fi
  grep -Eq 'accept_int.*Job' "$tmp/reject.log" || { cat "$tmp/reject.log" >&2; exit 1; }
  echo "$compiler passed lazy references, repeated false, mixed field writes and invalid argument"
done
