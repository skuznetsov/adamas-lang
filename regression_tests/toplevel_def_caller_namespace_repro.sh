#!/usr/bin/env bash
# A top-level def lowered on demand from a namespaced method must resolve its
# names in the program scope. The lowering kept the caller's class context, so
# 1.22.1's `def spawn` (concurrent.cr) called from Crystal::System::Signal
# resolved `Fiber::ExecutionContext::Scheduler` as
# Crystal::System::Fiber::ExecutionContext::Scheduler ("undefined method
# 'current'"), and a same-named namespaced type silently replaced the real one.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/toplevel-def-namespace.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# The callee path exists only at the top level; the caller's namespace has a
# same-named module without it.
cat > "$WORK_DIR/missing_in_caller_namespace.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Crystal::System::Fiber
end

class Fiber
  module ExecutionContext
    class Sched
      def spawn(*, name : String?) : Int32
        42
      end
    end

    module Scheduler
      def self.current : Sched
        Sched.new
      end
    end
  end
end

def spawn(*, name : String? = nil)
  Fiber::ExecutionContext::Scheduler.current.spawn(name: name)
end

module Crystal::System::Sig
  def self.go : Int32
    spawn(name: "signal-loop")
  end
end

LibC.exit(Crystal::System::Sig.go)
CR

# Both paths exist; the caller's namespace must not shadow the top-level type.
cat > "$WORK_DIR/shadowed_in_caller_namespace.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Fiber
  class Val
    def self.v : Int32
      1
    end
  end
end

module Crystal::System::Fiber
  class Val
    def self.v : Bool
      true
    end
  end
end

def pick(x : Int32) : Int32
  42
end

def pick(x : Bool) : Int32
  7
end

def get(*, name : String? = nil)
  Fiber::Val.v
end

module Crystal::System::Sig
  def self.go : Int32
    x = get(name: "n")
    pick(x)
  end
end

LibC.exit(Crystal::System::Sig.go)
CR

CASES=(
  "missing_in_caller_namespace:42"
  "shadowed_in_caller_namespace:42"
)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d top-level def namespace case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'top-level def namespace cases passed\n'
