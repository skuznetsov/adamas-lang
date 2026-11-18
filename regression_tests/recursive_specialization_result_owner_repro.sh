#!/usr/bin/env bash
# The result of an active recursive specialization belongs to its own input types.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/recursive-result.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/common.cr" <<'CR'
lib LibC
  fun putchar(c : Int32) : Int32
end

struct Letter
  def initialize(@code : Int32)
  end

  def code : Int32
    @code
  end
end

class Reader
  def copy(again, value)
    if again
      copy(false, value)
    else
      value
    end
  end

  def reverse_copy(again, value)
    if again
      self.reverse_copy(false, value)
    else
      value
    end
  end

  def change(again, value)
    if again
      change(false, Letter.new(67))
    else
      value
    end
  end
end

def number(value : Int32)
  value
end

def letter(value : Letter)
  value.code
end

r = Reader.new
CR

cp "$work/common.cr" "$work/valid.cr"
cat >> "$work/valid.cr" <<'CR'
LibC.putchar(letter(r.copy(true, Letter.new(65))))
LibC.putchar(number(r.copy(true, 66)))
LibC.putchar(number(r.reverse_copy(true, 67)))
LibC.putchar(letter(r.reverse_copy(true, Letter.new(68))))
LibC.putchar(10)
CR
cp "$work/common.cr" "$work/wrong.cr"
cat >> "$work/wrong.cr" <<'CR'
letter(r.copy(true, Letter.new(65)))
letter(r.copy(true, 66))
CR
cp "$work/common.cr" "$work/mixed.cr"
echo 'number(r.change(true, 67))' >> "$work/mixed.cr"
printf 'ABCD\n' > "$work/expected"

for tool in stock candidate; do
  if [[ "$tool" == stock ]]; then
    build=("$safe" "$stock" 120 4096 build --prelude=empty "${link[@]}")
    wrong_diag="expected argument #1 to 'letter' to be Letter, not Int32$"
    mixed_diag="expected argument #1 to 'number' to be Int32, not \\(Int32 \\| Letter\\)$"
  else
    build=("$safe" "$candidate" 120 4096 --no-prelude --no-ast-cache --no-llvm-cache)
    wrong_diag='no overload matches letter for argument types \(Int32\)$'
    mixed_diag='no overload matches number for argument types \(Int32 \| Letter\)$'
  fi
  "${build[@]}" "$work/valid.cr" -o "$work/program"
  "$safe" "$work/program" 8 512 > "$work/stdout"
  cmp "$work/expected" "$work/stdout"
  for control in wrong mixed; do
    if "${build[@]}" "$work/$control.cr" -o "$work/$control" > "$work/$control.log" 2>&1; then
      echo "$tool accepted the $control result as an incompatible type" >&2
      exit 1
    fi
    pattern_name="${control}_diag"
    grep -E "${!pattern_name}" "$work/$control.log"
  done
  echo "$tool passed recursive result ownership controls"
done
