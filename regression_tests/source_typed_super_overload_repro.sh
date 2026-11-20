#!/usr/bin/env bash
# A nested module super call selects the compatible overload and keeps its result.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/source-typed-super.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/nested_super.cr" <<'CR'
lib Native
  fun putchar(value : Int32) : Int32
end

abstract class IO
end

module EnumerableLike
  def render(separator : String = "") : String
    Native.putchar(84)
    separator
  end

  def render(io : IO, separator = "")
    Native.putchar(73)
    nil
  end
end

module IndexableLike
  include EnumerableLike

  def render(separator : String) : String
    super(separator)
  end
end

class Rendered
  include IndexableLike
end

Rendered.new.render("|")
Native.putchar(10)
CR

cat > "$work/incompatible_super.cr" <<'CR'
abstract class IO
end

module IoOnly
  def render(io : IO, separator = "")
    nil
  end
end

module Caller
  include IoOnly

  def render(separator : String)
    super(separator)
  end
end

class Rendered
  include Caller
end

Rendered.new.render("|")
CR

printf 'T\n' > "$work/expected"
for mode in original lazy eager; do
  case "$mode" in
    original)
      build=("$safe" "$original" 60 2048 build --prelude=empty --no-color "${link[@]}")
      negative='expected argument #1.*render.*to be IO, not String'
      ;;
    lazy)
      build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
      negative="(undefined method 'render' for Reference|no overload matches.*render)"
      ;;
    eager)
      build=(env ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
      negative="(undefined method 'render' for Reference|no overload matches.*render)"
      ;;
  esac
  "${build[@]}" "$work/nested_super.cr" -o "$work/positive" > "$work/positive.log" 2>&1 ||
    { cat "$work/positive.log" >&2; exit 1; }
  "$safe" "$work/positive" 5 512 > "$work/actual" 2> "$work/runtime.log" ||
    { cat "$work/runtime.log" >&2; exit 1; }
  cmp "$work/expected" "$work/actual"
  if "${build[@]}" "$work/incompatible_super.cr" -o "$work/negative" > "$work/negative.log" 2>&1; then
    echo "$mode compiled the incompatible super call" >&2
    exit 1
  fi
  grep -Ei "$negative" "$work/negative.log" >/dev/null || { cat "$work/negative.log" >&2; exit 1; }
  echo "$mode selected the String overload and rejected the incompatible unannotated call"
done
