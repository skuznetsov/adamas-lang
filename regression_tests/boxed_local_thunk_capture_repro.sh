#!/usr/bin/env bash
# A local captured by an earlier proc literal is boxed; later assignments write
# the box, but its SSA binding still names the pre-box value (a nilable
# branch-join phi when the local was first assigned inside an earlier `if`).
# A block lowered to a raw thunk (the callee has `return yield if ...`, so the
# block is not inlined) seeded its closure cell from that stale SSA value:
# stale data and a `Nil | String` argument type ("no overload matches foo").
# The thunk now captures the box's current payload, as an identifier read does.
# The compiler itself has the shape in AstToHir#register_function_type
# (`rt_text` captured by `resolve_module_return`, then read inside
# `with_type_param_map`).
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/boxed-local-thunk-capture.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

CASES=()

# add_case name expected-stderr-lines(|-separated) body
add_case() {
  CASES+=("$1")
  printf '%s\n' "$2" | tr '|' '\n' > "$WORK_DIR/$1.want"
  printf '%s\nexit 0\n' "$3" > "$WORK_DIR/$1.cr"
}

add_case reassigned_after_branch_box 'x-|2|y!' '
def foo(x : String) : String
  x
end

def wy(c : Bool, &)
  return yield if c
  yield
end

def m(a : String?, b : String?) : Nil
  if s = a
    t = s + "-"
    pr = -> { STDERR.puts t; t.size }
    STDERR.puts pr.call
  end
  if s = b
    t = s + "!"
    wy(true) do
      STDERR.puts foo(t)
    end
  end
end

m("x", "y")'

add_case thunk_write_back_reaches_box '3|ab!w|4' '
def foo(x : String) : String
  x
end

def wy(c : Bool, &)
  return yield if c
  yield
end

def written(a : String) : Nil
  if a.size > 0
    t = a + "-"
    pr = -> { t.size }
    STDERR.puts pr.call
  end
  if a.size > 0
    t = a + "!"
    wy(false) do
      t = foo(t) + "w"
    end
    STDERR.puts t
    STDERR.puts pr.call if pr
  end
end

written("ab")'

add_case instance_ensure_wrapper 'x!|2' '
class R
  @map = {} of String => String

  def foo(x : String) : String
    x
  end

  def with_map(extra : Hash(String, String), &)
    return yield if extra.empty?
    old = @map
    @map = old.merge(extra)
    begin
      yield
    ensure
      @map = old
    end
  end

  def m(a : String?, extra : Hash(String, String)) : Int32
    r = 0
    if s = a
      t = s + "-"
      pr = -> { t.size }
      with_map(extra) do
        r = pr.call
      end
    end
    if s = a
      t = s + "!"
      with_map(extra) do
        STDERR.puts foo(t)
      end
    end
    r
  end
end

STDERR.puts R.new.m("x", {"T" => "Int32"})'

stderr_of() {
  awk '/^=== STDERR ===$/ { on = 1; next } /^\[EXIT: / { on = 0 } on' "$1"
}

check_output() {
  local label="$1" name="$2" run_log="$3"
  if stderr_of "$run_log" | diff -u "$WORK_DIR/$name.want" - > "$WORK_DIR/$name.$label.diff"; then
    return 0
  fi
  return 1
}

# Original Crystal first, so the expected outputs themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${CASES[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if ! check_output orig "$name" "$WORK_DIR/$name.orig.run"; then
      printf 'ORACLE FAIL: original output differs for %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.diff" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${CASES[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 600 8192 "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ ! -x "$WORK_DIR/$name.adamas" ]]; then
    printf 'FAIL %s: compile failed\n' "$name" >&2
    grep -v '^\[RUN_SAFE' "$log" | grep -m3 -i 'error\|overload' >&2 || tail -5 "$log" >&2
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if check_output adamas "$name" "$run_log"; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: output differs\n' "$name" >&2
    cat "$WORK_DIR/$name.adamas.diff" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d boxed-local thunk-capture case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all boxed-local thunk-capture cases passed\n'
