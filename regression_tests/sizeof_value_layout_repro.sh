#!/usr/bin/env bash
# sizeof reports value layout, independent of boxed call representation.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/sizeof-value-layout.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cat > "$work/core.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Wide
  def initialize(@a : Int64, @b : Int64)
  end
end
struct Pair(T)
  def initialize(@a : T, @b : T)
  end
end
class Ref
  def initialize(@a : Int64, @b : Int64)
  end
end
wide = Wide.new(1_i64, 2_i64)
pair = Pair(Int64).new(3_i64, 4_i64)
LibC.exit(11) unless sizeof(Wide) == 16
LibC.exit(12) unless sizeof(Pair(Int64)) == 16
LibC.exit(13) unless sizeof(Ref) == 8
LibC.exit(14) unless sizeof(Int32) == 4
LibC.exit(0)
CR
cat > "$work/cold.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Space
  struct Plain
    @a : Int64
    @b : Int64
    def initialize(@a, @b)
    end
  end
  struct Pair(T)
    @a : T
    @b : T
    def initialize(@a, @b)
    end
    def self.bytes
      sizeof(self)
    end
  end
end
alias AliasPair = Space::Pair(Int64)
LibC.exit(11) unless sizeof(Space::Plain) == 16
LibC.exit(12) unless sizeof(Space::Pair(Int64)) == 16
LibC.exit(13) unless sizeof(AliasPair) == 16
LibC.exit(14) unless Space::Pair(Int64).bytes == 16
LibC.exit(0)
CR
cat > "$work/slice.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
LibC.exit(11) unless sizeof(Slice(UInt8)) == 16
LibC.exit(12) unless sizeof(Pointer(UInt8)) == 8
slice = "size".to_slice
LibC.exit(13) unless String.new(slice) == "size"
LibC.exit(0)
CR
cat > "$work/layout_controls.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
alias Word = UInt32
LibC.exit(11) unless sizeof(Word) == 4
LibC.exit(12) unless sizeof(StaticArray(UInt16, 3)) == 6
LibC.exit(13) unless sizeof(Tuple(Int8, Int64)) == 16
LibC.exit(0)
CR
for name in core cold slice layout_controls; do
  flags=()
  [[ "$name" == slice ]] || flags+=(--no-prelude)
  if ! "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$work/$name.cr" "${flags[@]}" -o "$work/$name" > "$work/$name.log" 2>&1; then
    cat "$work/$name.log"
    exit 1
  fi
  if ! "$root/scripts/run_safe.sh" "$work/$name" 5 512 >> "$work/$name.log" 2>&1; then
    cat "$work/$name.log"
    exit 1
  fi
  echo "PASS[$name]"
done
