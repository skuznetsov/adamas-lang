#!/usr/bin/env bash
# Keep postfix chains attached to same-line spaced parenthesized command arguments.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="${ADAMAS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal 2>/dev/null || true)}}"
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
elif [[ -d "$ROOT_DIR/../crystal/src" ]]; then
  CRYSTAL_STDLIB="$(cd "$ROOT_DIR/../crystal/src" && pwd -P)"
else
  echo "set CRYSTAL_PATH to the external Crystal stdlib source directory" >&2
  exit 2
fi
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -n "$ORIGINAL_CRYSTAL_BIN" && -x "$ORIGINAL_CRYSTAL_BIN" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "required compiler, safe runner, or Crystal stdlib path is unavailable" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spaced-parenthesized-command-argument.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

SOURCE="$WORK_DIR/spaced_parenthesized_command_argument.cr"
cat >"$SOURCE" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class ParenBox
  def value : Int32
    2
  end

  def inner : ParenBox
    self
  end

  def [](index : Int32) : Int32
    3
  end
end

class Wrapper
  def box : ParenBox
    ParenBox.new
  end
end

class Result
  def value : Int32
    4
  end
end

class Checker
  def expect_two(value : Int32)
    LibC.exit(11) unless value == 2
  end

  def expect_three(value : Int32)
    LibC.exit(12) unless value == 3
  end

  def expect_pair(first : Int32, second : Int32)
    LibC.exit(13) unless first == 2 && second == 3
  end
end

# `class` is a keyword token after the dot; this exercises the keyword-member parser branch.
class KeywordReceiver
  def class(value : Int32) : Int32
    value
  end
end

def expect_two(value : Int32)
  LibC.exit(21) unless value == 2
end

def expect_three(value : Int32)
  LibC.exit(22) unless value == 3
end

def expect_four(value : Int32)
  LibC.exit(24) unless value == 4
end

def expect_pair(first : Int32, second : Int32)
  LibC.exit(25) unless first == 2 && second == 3
end

def make_result(value : ParenBox) : Result
  Result.new
end

def no_arguments : Int32
  1
end

checker = Checker.new

# Same-line command calls retain postfix member, index, and binary suffixes in the argument.
expect_two (ParenBox.new).value
expect_three (ParenBox.new)[0]
expect_two (ParenBox.new).inner.value
expect_two (Wrapper.new).box.inner.value
expect_two (ParenBox.new).value + 0
expect_pair (ParenBox.new).inner.value, (ParenBox.new)[0]

# Identifier-member and keyword-member command calls use separate parser branches.
checker.expect_two (ParenBox.new).value
checker.expect_three (ParenBox.new)[0]
checker.expect_pair (ParenBox.new).value, (ParenBox.new)[0]
expect_two KeywordReceiver.new.class (ParenBox.new).value

# Adjacent explicit calls remain calls, with postfixes inside their explicit arguments.
expect_two((ParenBox.new).value)
expect_four(make_result(ParenBox.new).value)

# A newline still separates a zero-argument call from a parenthesized expression.
no_arguments
(ParenBox.new).value
CRYSTAL

compile() {
  local mode="$1" compiler="$2" status=0
  local output="$WORK_DIR/$mode.bin" log="$WORK_DIR/$mode.compile.log"
  if [[ "$mode" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/original.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$SOURCE" --no-debug \
      --link-flags="${CRYSTAL_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$SOURCE" --no-ast-cache --no-llvm-cache \
      --no-debug --no-prelude -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$mode]: compile exited $status" >&2
    tail -30 "$log" >&2
    return 1
  fi
}

run_and_assert() {
  local mode="$1" status=0
  local output="$WORK_DIR/$mode.stdout" log="$WORK_DIR/$mode.run.log"
  if RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode.run.resources" \
    "$SAFE_RUNNER" "$WORK_DIR/$mode.bin" 15 512 >"$output" 2>"$log"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$mode]: runtime exited $status" >&2
    cat "$log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$log"
  : >"$WORK_DIR/empty.expected"
  diff -u "$WORK_DIR/empty.expected" "$output"
  awk '/^=== STDERR ===$/ { capture=1; next } /^\[EXIT: / { capture=0 } capture { print }' \
    "$log" >"$WORK_DIR/$mode.stderr"
  diff -u "$WORK_DIR/empty.expected" "$WORK_DIR/$mode.stderr"
}

# Certify the semantics against original Crystal before running the candidate.
compile original "$ORIGINAL_CRYSTAL_BIN"
run_and_assert original
compile candidate "$COMPILER"
run_and_assert candidate
echo 'PASS[spaced-parenthesized-command-argument]: original and candidate exit 0 with exact empty stdout/stderr'
