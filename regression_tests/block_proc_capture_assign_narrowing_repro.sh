#!/usr/bin/env bash
# A captured local written inside a block that is not inlined (the callee
# yields more than once, so the block becomes a raw thunk with a closure cell)
# must read back as the value just written, as in Crystal's inlined block.
# `v = A.new; f(v)` read the cell's declared `Nil | A` instead, so stage 2
# stopped with "no overload matches lower_def_body_sequence for argument types
# (LoweringContext, Array(ExprId), Nil | AstArena | ...)". The proof must not
# survive a branch merge, a loop back edge, or a call that may run another
# thunk writing the same cell (`wrap(1) { v = nil }`).
# Positive cases exit 42 under original Crystal; negatives are rejected by it.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block-capture-assign.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  {
    cat <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class A
  def k : Int32
    40
  end
end

# Two yields: the block is lowered as a thunk, not inlined.
def wrap(extra : Int32, &)
  return yield if extra == 0
  yield
end

def f(x : A) : Int32
  x.k
end
HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

write_case assign_then_read '
def g(flag : Bool) : Int32
  if flag
    v = A.new
  end
  wrap(1) do
    v = A.new
    f(v)
  end
end

LibC.exit(g(false) &+ 2)'

write_case assign_then_bind_result '
def g(flag : Bool) : Int32
  if flag
    v = A.new
  end
  wrap(1) do
    v = A.new
    x = f(v)
    x &+ 0
  end
end

LibC.exit(g(true) &+ 2)'

write_case ivar_assign_in_method '
class H
  def initialize(@a : A)
  end

  def run(extra : Int32, &)
    return yield if extra == 0
    yield
  end

  def g(flag : Bool) : Int32
    if flag
      v = nil
    end
    run(1) do
      v = @a
      pick(v)
    end
  end

  def pick(x : A) : Int32
    x.k
  end
end

LibC.exit(H.new(A.new).g(true) &+ 2)'

write_case branch_write_merge_rejects '
def g(flag : Bool) : Int32
  if flag
    v = A.new
  end
  wrap(1) do
    if flag
      v = A.new
    end
    f(v)
  end
end

LibC.exit(g(false) &+ 2)'

write_case nested_thunk_write_rejects '
def g(flag : Bool) : Int32
  if flag
    v = A.new
  end
  wrap(1) do
    v = A.new
    wrap(1) { v = nil }
    f(v)
  end
end

LibC.exit(g(false) &+ 2)'

write_case loop_back_edge_rejects '
def g(flag : Bool) : Int32
  if flag
    v = A.new
  end
  wrap(1) do
    v = A.new
    i = 0
    while i < 2
      f(v)
      v = nil
      i = i &+ 1
    end
    40
  end
end

LibC.exit(g(false) &+ 2)'

POSITIVE=(assign_then_read assign_then_bind_result ivar_assign_in_method)
NEGATIVE=(branch_write_merge_rejects nested_thunk_write_rejects loop_back_edge_rejects)

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
    printf 'FAIL %s (run): exit %s, expected 42\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]] && grep -q "no overload matches" "$log"; then
    printf 'PASS %s (rejected)\n' "$name"
  else
    printf 'FAIL %s: expected an overload error\n' "$name"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d block capture assignment case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Block capture assignment cases passed\n'
