#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-included-metaclass.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > ordering.cr <<'CR'
lib LibC
  fun putchar(ch : Int32) : Int32
end

module Filtering(T)
  def choose(item : U.class) : UInt8 forall U
    65_u8
  end

  def choose(item) : Int32
    66
  end
end

module ReverseFiltering(T)
  def choose(item) : Int32
    66
  end

  def choose(item : U.class) : UInt8 forall U
    65_u8
  end
end

class Store(T)
  include Filtering(T)
end

class ReverseStore(T)
  include ReverseFiltering(T)
end

def emit(value : UInt8)
  LibC.putchar(value.to_i32)
end

def emit(value : Int32)
  LibC.putchar(value)
end

store = Store(Int32).new
other = ReverseStore(Int32).new
emit(store.choose(UInt8))
emit(store.choose(0_u8))
emit(other.choose(0_u8))
emit(other.choose(UInt8))
emit(store.choose(UInt8))
CR

cat > specificity.cr <<'CR'
lib LibC
  fun putchar(ch : Int32) : Int32
end

module Filtering(T)
  def choose(item : U.class) : Int32 forall U
    65
  end

  def choose(item : UInt8.class) : Int32
    66
  end

  def choose(item) : Int32
    67
  end

  def literal(item : UInt8.class) : Int32
    68
  end

  def literal(item) : Int32
    69
  end

  def accept_only_class(item : U.class) : Int32 forall U
    70
  end
end

class Store(T)
  include Filtering(T)
end

store = Store(Int32).new
{% if flag?(:invalid) %}
  LibC.putchar(store.accept_only_class(0_u8))
{% else %}
  LibC.putchar(store.choose(UInt8))
  LibC.putchar(store.choose(Int32))
  LibC.putchar(store.choose(0_u8))
  LibC.putchar(store.literal(UInt8))
  LibC.putchar(store.literal(Int32))
  LibC.putchar(store.literal(0_u8))
  LibC.putchar(store.accept_only_class(UInt8))
{% end %}
CR

cat > forwarding.cr <<'CR'
lib LibC
  fun putchar(ch : Int32) : Int32
end

module Forwarding(T)
  def marker(item : UInt8.class)
    65
  end

  def marker(item : UInt8)
    66
  end

  def forward(item)
    marker(item)
  end

  def pick(item : U.class) : U forall U
    7_u8
  end
end

class Store(T)
  include Forwarding(T)
end

store = Store(Int32).new
LibC.putchar(store.forward(UInt8))
LibC.putchar(store.forward(0_u8))
LibC.putchar(store.forward(UInt8))
LibC.putchar(store.pick(UInt8).to_i32 &+ 60)
CR

build_original() {
  "$safe" "$original" 60 4096 build "$1.cr" --prelude=empty --single-module \
    --no-debug "${original_flags[@]}" -o "$work/$1.original" "${@:2}"
}

build_candidate() {
  "$safe" "$candidate" 60 4096 "$1.cr" --no-prelude --no-debug \
    --no-ast-cache --no-llvm-cache -o "$work/$1.candidate" "${@:2}"
}

for test in ordering specificity forwarding; do
  build_original "$test" > "$test.original.log" 2>&1 || { cat "$test.original.log" >&2; exit 1; }
  "$safe" "$work/$test.original" 5 512 > "$test.original.out"
done
printf ABBAA | diff -u - ordering.original.out
printf BACDEEF | diff -u - specificity.original.out
printf ABAC | diff -u - forwarding.original.out
if build_original specificity -Dinvalid --no-codegen > invalid.original.log 2>&1; then
  echo 'Crystal accepted an instance for a U.class restriction' >&2
  exit 1
fi
grep -Fq 'to be U.class, not UInt8' invalid.original.log

for eager in 0 1; do
  if [[ "$eager" == 1 ]]; then
    export ADAMAS_EAGER_HIR=1
  fi
  for test in ordering specificity forwarding; do
    build_candidate "$test" > "$test.candidate.log" 2>&1 || { cat "$test.candidate.log" >&2; exit 1; }
    "$safe" "$work/$test.candidate" 5 512 > "$test.candidate.out"
    diff -u "$test.original.out" "$test.candidate.out"
  done
  if build_candidate specificity -Dinvalid --no-link --emit hir > invalid.candidate.log 2>&1; then
    echo 'Adamas accepted an instance for a U.class restriction' >&2
    exit 1
  fi
  grep -Eq 'error:.*(incompatible explicit arguments|no overload matches).*accept_only_class' invalid.candidate.log
done

printf 'PASS included overloads preserve class-object and instance arguments\n'
