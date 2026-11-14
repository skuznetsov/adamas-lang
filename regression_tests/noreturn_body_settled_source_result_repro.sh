#!/usr/bin/env bash
# Regression: a completed unannotated method whose every exit is a proven
# noreturn effect (`def self.exit(status); LibC.exit(status); end`) is a
# settled source result even though its ABI return slot is Void.
#
# When such a producer was refused at the force-lowering depth cap, its
# suspended consumer was replayed after the producer completed, but the
# settle check only authenticated Void bodies that end in a Return. The bottom
# body never settled, so every relayed consumer up the chain stayed pending and
# compilation failed with "pending source result Sys.exit$Int32 in
# Pr.exit$Int32" (prelude hello: Crystal::System::Process.exit through exit and
# Crystal::Scheduler#fatal_resume_error to #validate_resumable).
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-noreturn_body_settled_source_result.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > depth_refused_bottom_producer.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Sys
  def self.exit(status)
    LibC.exit(status)
  end
end
module Pr
  def self.exit(status = 0) : NoReturn
    Sys.exit(status)
  end
end
def exit(status = 0) : NoReturn
  Pr.exit(status)
end
module Sch
  def self.fatal(x, msg)
    exit 1
  end
  def self.validate(x : Int32)
    if x > 5
      fatal(x, "bad")
    end
    x
  end
  def self.resume(x : Int32)
    validate(x) &+ 1
  end
end
LibC.exit(Sch.resume(3) &+ 24)
CR

cat > nested_bottom_helper.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Sys
  def self.really_exit(status)
    LibC.exit(status)
  end
  def self.exit(status)
    really_exit(status)
  end
end
module Pr
  def self.exit(status = 0) : NoReturn
    Sys.exit(status)
  end
end
def exit(status = 0) : NoReturn
  Pr.exit(status)
end
module Sch
  def self.fatal(x, msg)
    exit 1
  end
  def self.validate(x : Int32)
    if x > 5
      fatal(x, "bad")
    end
    x
  end
  def self.resume(x : Int32)
    validate(x) &+ 1
  end
end
LibC.exit(Sch.resume(3) &+ 24)
CR

cat > runtime_exit_path_status.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Sys
  def self.exit(status)
    LibC.exit(status)
  end
end
module Pr
  def self.exit(status = 0) : NoReturn
    Sys.exit(status)
  end
end
def exit(status = 0) : NoReturn
  Pr.exit(status)
end
module Sch
  def self.fatal(x, msg)
    exit x &- 3
  end
  def self.validate(x : Int32)
    if x > 5
      fatal(x, "bad")
    end
    x
  end
  def self.resume(x : Int32)
    validate(x) &+ 1
  end
end
LibC.exit(Sch.resume(9) &+ 24)
CR

cat > bottom_consumer_over_returning_producer.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Sys
  def self.exit(status)
    if status > 100
      return
    end
    LibC.exit(status)
  end
end
module Pr
  def self.exit(status = 0)
    Sys.exit(status)
    LibC.exit(status &- 100)
  end
end
def exit(status = 0)
  Pr.exit(status)
end
module Sch
  def self.fatal(x, msg)
    exit 128
  end
  def self.validate(x : Int32)
    if x > 5
      fatal(x, "bad")
    end
    x
  end
  def self.resume(x : Int32)
    validate(x) &+ 1
  end
end
LibC.exit(Sch.resume(3) &+ 24)
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

check depth_refused_bottom_producer 28
check nested_bottom_helper 28
check runtime_exit_path_status 6
check bottom_consumer_over_returning_producer 28

[[ $fail == 0 ]] || exit 1
printf 'PASS noreturn_body_settled_source_result\n'
