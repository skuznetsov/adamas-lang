#!/usr/bin/env bash
# `::name args` calls the top-level method `name`, skipping every enclosing
# owner, and takes command arguments like a bare identifier. Object's getter!
# macro expands to `::raise ::NilAssertionError.new(...)`. The parser stopped
# the absolute path after `::raise` and continued it across the space into
# `::raise::NilAssertionError`, so prelude hello failed with "undefined method
# 'new' for raise::NilAssertionError". `::h "x"` was parsed as two statements
# (the call silently dropped), `f(::h "x")` was a parse error, and HIR lowered
# a `::name` callee as a type path: `::g(40)` demanded `.call` on Int32 and
# `::g 42` became the generic instance `g(42)`. A same-named instance or class
# method of the enclosing owner must not be picked. Positive cases exit 42
# under original Crystal; an undefined global stays rejected.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/absolute-global-call.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  cat > "$WORK_DIR/$name.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Err
  def initialize(@message : String)
  end
end

def raise(e : Err) : NoReturn
  LibC.exit(42)
end

def g(x : Int32) : Int32
  x
end

def h(s : String) : Int32
  42
end

def z : Int32
  42
end

$body
CR
}

write_case raise_new_arg 'def check(x : Int32?) : Int32
  if x.nil?
    ::raise ::Err.new("x")
  end
  1
end

check(nil)
LibC.exit(3)'
write_case nested_command_arg 'LibC.exit(::g 42)'
write_case nested_string_arg 'LibC.exit(::h "x")'
write_case statement_string_arg 'def m : Int32
  ::h "x"
end

LibC.exit(m)'
write_case statement_number_arg 'def m : Int32
  ::g 42
end

LibC.exit(m)'
write_case paren_args 'LibC.exit(::h("x"))'
write_case zero_args 'LibC.exit(::z)'
write_case owner_namesakes 'class C
  def g(x : Int32) : Int32
    1
  end

  def self.g(x : Int32) : Int32
    2
  end

  def run : Int32
    ::g 42
  end

  def self.srun : Int32
    ::g(40) &+ ::g 2
  end
end

LibC.exit(C.new.run == 42 && C.srun == 42 ? 42 : 3)'
write_case untyped_namesake 'def u(x)
  x &+ 2
end

class C
  def u(x)
    0
  end

  def run
    ::u 40
  end
end

LibC.exit(C.new.run)'
write_case block_arg 'def y(x : Int32, &) : Int32
  yield x
end

class C
  def y(x : Int32, &) : Int32
    0
  end

  def run : Int32
    ::y 41 { |v| v &+ 1 }
  end
end

LibC.exit(C.new.run)'
# Negative: only the owner defines `nope`; `::nope` must not find it.
write_case owner_only_rejected 'class C
  def nope(x : Int32) : Int32
    42
  end

  def run : Int32
    ::nope 1
  end
end

LibC.exit(C.new.run)'

POSITIVE=(raise_new_arg nested_command_arg nested_string_arg statement_string_arg
  statement_number_arg paren_args zero_args owner_namesakes untyped_namesake block_arg)
NEGATIVE=(owner_only_rejected)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${POSITIVE[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "42" ]]; then
      printf 'ORACLE FAIL: original %s did not exit 42\n' "$name" >&2
      exit 2
    fi
  done
  for name in "${NEGATIVE[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${POSITIVE[@]}"; do
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
  if [[ "$(exit_code_of "$run_log")" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run exit %s)\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" == "0" ]]; then
    printf 'FAIL %s (accepted)\n' "$name"
    failures=$((failures + 1))
  else
    printf 'PASS %s (rejected)\n' "$name"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
