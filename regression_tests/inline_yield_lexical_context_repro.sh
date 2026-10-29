#!/usr/bin/env bash
# Inlined yielding callees must use their own lexical visibility context,
# while caller-owned block bodies keep the caller's access restrictions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_PATH="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inline_yield_lexical_context.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ ! -x "$SAFE_RUNNER" || ! -x "$COMPILER" || ! -x "$ORIGINAL_CRYSTAL_BIN" || ! -d "$CRYSTAL_PATH" ]]; then
  echo "FAIL: compiler, run_safe.sh, original Crystal, or installed stdlib is unavailable" >&2
  exit 2
fi

if ! CRYSTAL_PATH="$CRYSTAL_PATH" "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 15 512 --version \
    >"$WORK_DIR/original-version.log" 2>&1; then
  echo "FAIL: original Crystal --version invocation failed" >&2
  cat "$WORK_DIR/original-version.log" >&2
  exit 2
fi
sed -n '/^Crystal /p' "$WORK_DIR/original-version.log"

cat >"$WORK_DIR/direct_control.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Guarded
  class Context
    protected def answer : Int32
      42
    end

    def yield_then_answer(&) : Int32
      yield
      Guarded::Context.new.answer
    end
  end
end

LibC.exit(Guarded::Context.new.yield_then_answer { 1 } == 42 ? 0 : 7)
CR

cat >"$WORK_DIR/unrelated_mixin_positive.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Guarded
  class Context
    protected def answer : Int32
      42
    end

    def yield_then_answer(&) : Int32
      yield
      Guarded::Context.new.answer
    end
  end
end

module Unrelated
  module Methods
    def via_mixin : Int32
      Guarded::Context.new.yield_then_answer do
        1
      end
    end
  end

  class Caller
    include Methods
  end
end

LibC.exit(Unrelated::Caller.new.via_mixin == 42 ? 0 : 7)
CR

cat >"$WORK_DIR/nested_mixin_positive.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Guarded
  module NestedYieldingMethods
    def yield_then_answer(&) : Int32
      yield
      Guarded::Context.new.answer
    end
  end

  class Context
    protected def answer : Int32
      42
    end

    include NestedYieldingMethods
  end
end

module Unrelated
  module Methods
    def via_mixin : Int32
      Guarded::Context.new.yield_then_answer { 1 }
    end
  end

  class Caller
    include Methods
  end
end

LibC.exit(Unrelated::Caller.new.via_mixin == 42 ? 0 : 12)
CR

cat >"$WORK_DIR/caller_block_negative.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Guarded
  class Context
    protected def answer : Int32
      42
    end

    def yield_only(&) : Int32
      yield
      0
    end
  end
end

module Unrelated
  module Methods
    def via_mixin : Int32
      Guarded::Context.new.yield_only do
        Guarded::Context.new.answer
      end
    end
  end

  class Caller
    include Methods
  end
end

LibC.exit(Unrelated::Caller.new.via_mixin == 42 ? 0 : 13)
CR

failures=0

run_positive() {
  local stage="$1"
  local fixture="$2"
  local bin="$WORK_DIR/$fixture.$stage"
  local log="$WORK_DIR/$fixture.$stage.log"
  if [[ "$stage" == original ]]; then
    if ! CRYSTAL_PATH="$CRYSTAL_PATH" "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 4096 \
        build --prelude=empty "$WORK_DIR/$fixture.cr" -o "$bin" >"$log" 2>&1; then
      echo "FAIL[$stage/$fixture]: compile"
      cat "$log"
      failures=$((failures + 1))
      return
    fi
  else
    if ! CRYSTAL_PATH="$CRYSTAL_PATH" "$SAFE_RUNNER" "$COMPILER" 180 4096 \
        "$WORK_DIR/$fixture.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
        -o "$bin" >"$log" 2>&1; then
      echo "FAIL[$stage/$fixture]: compile"
      cat "$log"
      failures=$((failures + 1))
      return
    fi
  fi

  if ! "$SAFE_RUNNER" "$bin" 5 512 >"$WORK_DIR/$fixture.$stage.run.log" 2>&1; then
    echo "FAIL[$stage/$fixture]: runtime"
    cat "$WORK_DIR/$fixture.$stage.run.log"
    failures=$((failures + 1))
  else
    echo "PASS[$stage/$fixture]"
  fi
}

expect_protected_rejection() {
  local stage="$1"
  local fixture=caller_block_negative
  local bin="$WORK_DIR/$fixture.$stage"
  local log="$WORK_DIR/$fixture.$stage.log"
  local rc=0
  if [[ "$stage" == original ]]; then
    CRYSTAL_PATH="$CRYSTAL_PATH" "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 4096 \
      build --prelude=empty "$WORK_DIR/$fixture.cr" -o "$bin" >"$log" 2>&1 || rc=$?
  else
    CRYSTAL_PATH="$CRYSTAL_PATH" "$SAFE_RUNNER" "$COMPILER" 180 4096 \
      "$WORK_DIR/$fixture.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$bin" >"$log" 2>&1 || rc=$?
  fi

  if (( rc == 0 )); then
    echo "FAIL[$stage/$fixture]: caller block unexpectedly gained protected access"
    failures=$((failures + 1))
  elif grep -Eq "protected method.*answer.*called for Guarded::Context" "$log"; then
    echo "PASS[$stage/$fixture]: protected caller-block access rejected"
  else
    echo "FAIL[$stage/$fixture]: compilation failed for an unrelated reason (status $rc)"
    cat "$log"
    failures=$((failures + 1))
  fi
}

# Establish the original compiler's behavior for every fixture before invoking
# the candidate compiler, so candidate results cannot qualify the oracle.
for fixture in direct_control unrelated_mixin_positive nested_mixin_positive; do
  run_positive original "$fixture"
done
expect_protected_rejection original
if (( failures > 0 )); then
  echo "FAIL: installed Crystal oracle did not qualify all cases"
  exit 2
fi

for fixture in direct_control unrelated_mixin_positive nested_mixin_positive; do
  run_positive candidate "$fixture"
done
expect_protected_rejection candidate

if (( failures > 0 )); then
  echo "FAIL: $failures inline-yield lexical-context cases"
  exit 1
fi

echo "PASS: inline-yield lexical context and caller-block visibility"
