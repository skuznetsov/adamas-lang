#!/usr/bin/env bash
# Regression: `in Tuple(Int32, Bool)` is a type test even when no prelude
# template registers Tuple. resolved_case_condition_type_name? only accepted
# registered type names, so the no-prelude arm was lowered as a value
# comparison, the `in Errno` arm was the only narrowing, and the annotated
# `{FD::Handle, Bool}` return saw the enum (`Sys::F.open$Int32 must return
# Tuple(Int32, Bool), but it is returning Sys::Errno ...`). Covered: the arm
# spelled with the builtin element type and with the alias.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-builtin-generic-case-type-arm.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > tuple_arm_builtin_spelling.cr <<'CR'
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
    abstract def open(x : Int32) : {Sys::FD::Handle, Bool} | Errno
  end

  class Poll < Loop
    def open(x : Int32) : {Sys::FD::Handle, Bool} | Errno
      x > 0 ? {x, true} : Errno::A
    end
  end

  module F
    def self.open(x : Int32) : {FD::Handle, Bool}
      l = Poll.new.as(Loop)
      case result = l.open(x)
      in Tuple(Int32, Bool)
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

fd, b = Sys::F.open(5)
LibC.exit(b ? fd &+ 10 : 1)
CR

cat > tuple_arm_alias_spelling.cr <<'CR'
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
    abstract def open(x : Int32) : {Sys::FD::Handle, Bool} | Errno
  end

  class Poll < Loop
    def open(x : Int32) : {Sys::FD::Handle, Bool} | Errno
      x > 0 ? {x, true} : Errno::A
    end
  end

  module F
    def self.open(x : Int32) : {FD::Handle, Bool}
      l = Poll.new.as(Loop)
      case result = l.open(x)
      in Tuple(FD::Handle, Bool)
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

fd, b = Sys::F.open(5)
LibC.exit(b ? fd &+ 10 : 1)
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

check tuple_arm_builtin_spelling 15
check tuple_arm_alias_spelling 15

[[ $fail == 0 ]] || exit 1
printf 'PASS builtin generic case type arm\n'
