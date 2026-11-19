#!/usr/bin/env bash
# A successful descendant check narrows the source type used for return validation.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/descendant-guard-result.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1 ADAMAS_LLVM_CACHE=0
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/positive.cr" <<'CRYSTAL'
lib GuardedResultC
  fun getchar : Int32
  fun putchar(c : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def raise(message : String) : NoReturn
  GuardedResultC.exit(1)
end

abstract class GuardedBase
end

class GuardedLeaf < GuardedBase
  def initialize(@code : Int32)
  end

  def code
    @code
  end
end

class GuardedSecond < GuardedBase
  def code
    68
  end
end

class GuardedSibling < GuardedBase
  def code
    88
  end
end

enum GuardedRedirect
  Inherit
end

def broad_value(code : Int32) : GuardedBase | GuardedRedirect
  if code == 65
    GuardedLeaf.new(65)
  elsif code == 66
    GuardedSibling.new
  else
    GuardedRedirect::Inherit
  end
end

def select_result(value : GuardedBase | GuardedRedirect, fallback : GuardedLeaf) : GuardedLeaf
  case value
  in GuardedLeaf
    value
  in GuardedBase
    fallback
  in GuardedRedirect
    fallback
  end
end

def select_with_if(value : GuardedBase | GuardedRedirect, fallback : GuardedLeaf) : GuardedLeaf
  if value.is_a?(GuardedLeaf)
    value
  else
    fallback
  end
end

def broad_object(code : Int32) : GuardedBase
  if code == 65
    GuardedLeaf.new(65)
  elsif code == 68
    GuardedSecond.new
  else
    GuardedSibling.new
  end
end

def select_from_set(value : GuardedBase, fallback : GuardedLeaf) : GuardedLeaf | GuardedSecond
  case value
  when GuardedLeaf, GuardedSecond
    value
  else
    fallback
  end
end

fallback = GuardedLeaf.new(90)
code = GuardedResultC.getchar
GuardedResultC.putchar(select_result(broad_value(code), fallback).code)
GuardedResultC.putchar(select_with_if(broad_value(code), fallback).code)
GuardedResultC.putchar(select_from_set(broad_object(code), fallback).code)
GuardedResultC.putchar(10)
CRYSTAL

# Selecting the ancestor alone does not prove the returned value is a leaf.
awk '{ if (replace) { print "    value"; replace=0; next } print; if ($0 == "  in GuardedBase") replace=1 }' \
  "$work/positive.cr" > "$work/wrong_return.cr"
printf 'AAA\nZZZ\nZZZ\nZZD\n' > "$work/expected"

for compiler in original candidate; do
  if [[ "$compiler" == original ]]; then
    build=("$safe" "$original" 60 4096 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 60 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$work/positive.cr" -o "$work/$compiler"
  for code in A B C D; do
    printf %s "$code" | "$safe" "$work/$compiler" 8 512
  done > "$work/stdout"
  cmp "$work/expected" "$work/stdout"
  status=0
  "${build[@]}" "$work/wrong_return.cr" -o "$work/$compiler-invalid" > "$work/error" 2>&1 || status=$?
  if [[ "$status" != 1 || -e "$work/$compiler-invalid" ]] || ! rg -q 'must return GuardedLeaf' "$work/error"; then
    cat "$work/error" >&2
    exit 1
  fi
done
echo 'PASS: descendant guards narrow nominal results without admitting the ancestor.'
