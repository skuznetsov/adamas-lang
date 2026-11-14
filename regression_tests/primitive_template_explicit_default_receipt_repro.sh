#!/usr/bin/env bash
# Regression: an explicit-argument call and a nilary call of an inherited Int
# method on the same numeric primitive share one padded physical symbol
# (`UInt32#fmt$Int32_Int32_Bool`) and must share one source authority.
#
# The defaulted explicit call materialized the body through the exact-source
# binder, which recorded no primitive-template receipt. The later nilary
# selection then found an unbound body and raised "primitive-template physical
# body was materialized before source binding" (prelude hello:
# `first.to_s(16)` in IO#read_char_with_bytesize, then `value.to_s` in
# Crystal::DWARF::FORM#to_s). The reverse call order always worked.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-primitive_template_explicit_default_receipt.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > explicit_then_nilary.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct UInt32
end

struct Int
  def fmt(base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : Int32
    base &+ precision
  end
end

def show(v : UInt32) : Int32
  v.fmt
end

a = 7_u32.fmt(16)
b = show(3_u32)
LibC.exit(a &+ b)
CR

cat > nilary_then_explicit.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct UInt32
end

struct Int
  def fmt(base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : Int32
    base &+ precision
  end
end

def show(v : UInt32) : Int32
  v.fmt
end

b = show(3_u32)
a = 7_u32.fmt(16)
LibC.exit(a &+ b)
CR

cat > nested_nilary_with_sibling_overload.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct UInt32
  def dummy : Int32
    0
  end
end


struct Int
  def fmt(base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : Int32
    base &+ precision
  end

  def fmt(io : Bool, base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : Int32
    base &+ precision &+ 100
  end
end

def show(v : UInt32) : Int32
  v.fmt
end

a = 7_u32.fmt(16)
b = show(3_u32)
LibC.exit(a &+ b)
CR

cat > nested_nilary.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct UInt32
  def dummy : Int32
    0
  end
end


struct Int
  def fmt(base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : Int32
    base &+ precision
  end
end

def lvl3(v : UInt32) : Int32
  v.fmt
end

def lvl2(v : UInt32) : Int32
  lvl3(v)
end

def lvl1(v : UInt32) : Int32
  lvl2(v)
end

a = 7_u32.fmt(16)
b = lvl1(3_u32)
LibC.exit(a &+ b)
CR

exit_code() {
  local out
  out="$("$safe" "$1" 5 256 2>&1 || true)"
  printf '%s\n' "$out" | sed -n 's/^\[EXIT: \([0-9-]*\)\].*/\1/p' | tail -1
}

fail=0
check() {
  local case_name="$1" want="$2" got_original got_candidate
  "$safe" "$original" 120 4096 build "$case_name.cr" --prelude=empty --single-module \
    --no-debug "${original_flags[@]}" -o "$case_name.original" > "$case_name.original.log" 2>&1 ||
    { cat "$case_name.original.log" >&2; echo "ORACLE_BUILD_FAIL $case_name"; fail=1; return; }
  got_original="$(exit_code "$work/$case_name.original")"
  if [[ "$got_original" != "$want" ]]; then
    echo "ORACLE_MISMATCH $case_name: original=$got_original expected=$want"; fail=1; return
  fi
  if ! "$safe" "$candidate" 120 4096 "$case_name.cr" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$case_name.candidate" > "$case_name.candidate.log" 2>&1; then
    echo "FAIL $case_name: candidate compile failed"
    grep -a -m3 -i error "$case_name.candidate.log" || true
    fail=1; return
  fi
  got_candidate="$(exit_code "$work/$case_name.candidate")"
  if [[ "$got_candidate" != "$want" ]]; then
    echo "FAIL $case_name: candidate=$got_candidate expected=$want"; fail=1; return
  fi
  echo "ok $case_name"
}

check explicit_then_nilary 28
check nilary_then_explicit 28
check nested_nilary_with_sibling_overload 28
check nested_nilary 28

[[ $fail == 0 ]] || exit 1
printf 'PASS primitive_template_explicit_default_receipt\n'
