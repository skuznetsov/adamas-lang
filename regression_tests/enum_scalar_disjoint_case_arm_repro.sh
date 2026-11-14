#!/usr/bin/env bash
# Regression: an enum value is never an instance of a scalar builtin or a
# container, so `in Int32` over `Int32 | Errno` (Errno an enum) must exclude the
# enum arm. Enums lower through their integer carrier and have no ClassInfo, so
# statically_is_a_type?(Errno, Int32) was undecided and the arm kept the enum
# (`Sys::F.open$Int32 must return Int32, but it is returning Int32 | Sys::Errno`).
# Covered: namespaced enum, top-level enum, and the reversed union spelling.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-enum-scalar-disjoint-case-arm.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > namespaced_enum.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Sys
  module FD
    alias Handle = Int32
  end

  enum Errno
    A
    B
  end

  abstract class Loop
    abstract def open(x : Int32) : Int32 | Errno
  end

  class Poll < Loop
    def open(x : Int32) : Int32 | Errno
      x > 0 ? x : Errno::A
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

cat > toplevel_enum.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum Errno
  A
  B
end

module Sys
  module FD
    alias Handle = Int32
  end


  abstract class Loop
    abstract def open(x : Int32) : Int32 | Errno
  end

  class Poll < Loop
    def open(x : Int32) : Int32 | Errno
      x > 0 ? x : Errno::A
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

cat > reversed_union_spelling.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Sys
  module FD
    alias Handle = Int32
  end

  enum Errno
    A
    B
  end

  abstract class Loop
    abstract def open(x : Int32) : Errno | Int32
  end

  class Poll < Loop
    def open(x : Int32) : Errno | Int32
      x > 0 ? x : Errno::A
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

check namespaced_enum 15
check toplevel_enum 15
check reversed_union_spelling 15

[[ $fail == 0 ]] || exit 1
printf 'PASS enum scalar disjoint case arm\n'
