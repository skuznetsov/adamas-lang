#!/usr/bin/env bash
# Crystal types a call by its body when that is narrower than the return
# annotation: `def index : Idx?` whose every path returns an Idx types
# `e.index` as Idx (Object's getter! expands to exactly this shape for
# `getter! index : Arena::Index?`). Adamas typed the call by the annotation,
# so passing the result to an Idx parameter failed overload resolution
# ("undefined method 'index' for Nil" in prelude hello). The callee ABI stays
# the annotated union; a direct call of an already lowered body is unwrapped to
# the single variant all its returns produce. A body that can return nil keeps
# the union and stays rejected. Known gap: a bare top-level callee lowered
# after its caller keeps the annotation. Positive cases exit 42 under original
# Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/annotated-return-narrowing.XXXXXX")"

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

def take(x : Int32) : Int32
  x &+ 1
end

$body
CR
}

write_case method_arg 'class C
  @x : Int32? = 41

  def f : Int32?
    if (v = @x).nil?
      LibC.exit(1)
    else
      v
    end
  end
end

LibC.exit(take(C.new.f))'
write_case local_assign 'class C
  @x : Int32? = 41

  def f : Int32?
    if (v = @x).nil?
      LibC.exit(1)
    else
      v
    end
  end
end

r = C.new.f
LibC.exit(r &+ 1)'
write_case struct_block_arg 'module Outer
  struct Idx
    def initialize(@v : Int32)
    end

    def v : Int32
      @v
    end
  end

  struct Ev
    @index : Idx??

    def initialize(@index = nil)
    end

    def index : Idx?
      if (value = @index).nil?
        LibC.exit(1)
      else
        value
      end
    end
  end
end

class Ar
  def get?(i : Outer::Idx, &) : Int32
    yield i.v
  end
end

e = Outer::Ev.new(Outer::Idx.new(42))
LibC.exit(Ar.new.get?(e.index) { |x| x })'
# Negative: the body returns the nilable ivar itself.
write_case nilable_body_rejected 'class C
  @x : Int32? = 41

  def f : Int32?
    @x
  end
end

LibC.exit(take(C.new.f))'
# Negative: an early `return nil` keeps Nil in the body type.
write_case early_nil_return_rejected 'class C
  @x : Int32? = 41

  def f : Int32?
    return nil if @x.nil?
    41
  end
end

LibC.exit(take(C.new.f))'

POSITIVE=(method_arg local_assign struct_block_arg)
NEGATIVE=(nilable_body_rejected early_nil_return_rejected)

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
