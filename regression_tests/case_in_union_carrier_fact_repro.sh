#!/usr/bin/env bash
# Regression: `case result = loop.open(x)` over a virtual call returning
# `Int32 | Errno` (Errno a class) must narrow the `in Int32` arm to Int32.
# The call result is an untracked union-carrier fact; register_is_a_narrowed_local
# kept that whole carrier as one undecided alternative, so the narrowed local
# still claimed the excluded arm and the annotated return failed
# (`Sys::F.open$Int32 must return Int32, but it is returning Int32 | Sys::Errno`;
# prelude: Crystal::System::File.open over EventLoop#open).
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-case-in-union-carrier-fact.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > class_errno_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Sys
  module FD
    alias Handle = Int32
  end

  class Errno
  end

  abstract class Loop
    abstract def open(x : Int32) : Int32 | Errno
  end

  class Poll < Loop
    def open(x : Int32) : Int32 | Errno
      x > 0 ? x : Errno.new
    end
  end

  module F
    def self.open(x : Int32) : Int32
      l = Poll.new.as(Loop)
      case result = l.open(x)
      in Int32
        result
      in Errno
        LibC.exit(3)
      end
    end
  end
end

def raise(msg) : NoReturn
  LibC.exit(99)
end

LibC.exit(Sys::F.open(5) &+ 10)
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

check class_errno_arm 15

[[ $fail == 0 ]] || exit 1
printf 'PASS case in union carrier fact\n'
