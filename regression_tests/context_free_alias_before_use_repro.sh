#!/usr/bin/env bash
# Regression: Crystal declares every alias before typing any method, so a
# signature may spell an alias declared later in source order
# (event_loop/polling.cr uses `{System::FileDescriptor::Handle, Bool}` before
# system/unix/file_descriptor.cr declares `alias Handle = Int32`). Registration
# resolved the signature eagerly and minted a phantom class for the unknown
# alias, so the return type was a phantom tuple and `is_a?(Tuple(Int32, Bool))`
# or the `in` arm failed. Covered: a nested namespace alias, a top-level alias,
# and the File.open/EventLoop shape.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-context-free-alias-before-use.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > nested_namespace_alias.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Crystal
  class Polling
    def open(x : Int32) : {System::FileDescriptor::Handle, Bool}
      {x, true}
    end
  end

  module System::FileDescriptor
    alias Handle = Int32
  end
end

r = Crystal::Polling.new.open(5)
LibC.exit(r.is_a?(Tuple(Int32, Bool)) ? r[0] &+ 10 : 1)
CR

cat > toplevel_alias.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Polling
  def open(x : Int32) : {H, Bool}
    {x, true}
  end
end

alias H = Int32

r = Polling.new.open(5)
LibC.exit(r.is_a?(Tuple(Int32, Bool)) ? r[0] &+ 10 : 1)
CR

cat > file_open_event_loop.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def raise(msg) : NoReturn
  LibC.exit(99)
end

enum Errno
  A
  B
end

module Crystal
  abstract class EventLoop
    module FileDescriptor
      abstract def open(x : Int32) : {System::FileDescriptor::Handle, Bool} | Errno
    end

    include FileDescriptor
  end

  class EventLoop::Polling < EventLoop
    def open(x : Int32) : {System::FileDescriptor::Handle, Bool} | Errno
      x > 0 ? {x, true} : Errno::A
    end
  end

  module System::File
    def self.open(x : Int32) : {FileDescriptor::Handle, Bool}
      case result = EventLoop::Polling.new.as(EventLoop).open(x)
      in Tuple(FileDescriptor::Handle, Bool)
        result
      in Errno
        raise "x"
      end
    end
  end

  module System::FileDescriptor
    alias Handle = Int32
  end
end

fd, b = Crystal::System::File.open(5)
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

check nested_namespace_alias 15
check toplevel_alias 15
check file_open_event_loop 15

[[ $fail == 0 ]] || exit 1
printf 'PASS context free alias before use\n'
