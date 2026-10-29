#!/usr/bin/env bash
# A type nested in a generic module or class lives in the generic type's
# namespace: `Indexable::ItemIterator`, not `Indexable(T)::ItemIterator`.
# V2 built the nested name from the owner's header spelling (module names
# keep their `(T)` parameters), so `Array#each` returned a phantom template
# `Indexable(T)::ItemIterator(...)` and `.with_index` on it failed with
# "undefined method 'new' for Iterator::WithIndexIterator(Indexable(T)::...)".
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested-generic-namespace.XXXXXX")"

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

add_case stdlib_item_iterator 'Indexable::ItemIterator(Array(Int32), Int32)' '
x = [10, 20].each
STDERR.puts typeof(x)'

add_case stdlib_with_index_iterator 'Iterator::WithIndexIterator(Indexable::ItemIterator(Array(Int32), Int32), Int32, Int32)|[10, 21]' '
x = [10, 20].each.with_index
STDERR.puts typeof(x)
STDERR.puts x.map { |v, i| v + i }.to_a'

add_case user_generic_module 'Ix::ItemIt(Arr(Int32), Int32)|9' '
module Ix(T)
  def items
    ItemIt(self, T).new(self)
  end

  class ItemIt(A, T)
    def initialize(@a : A)
    end

    def a
      @a
    end
  end
end

class Arr(T)
  include Ix(T)

  def initialize(@v : T)
  end

  def v
    @v
  end
end

x = Arr(Int32).new(9).items
STDERR.puts typeof(x)
STDERR.puts x.a.v'

add_case user_generic_class 'Ou::In(Int32)|4' '
class Ou(T)
  def mk(v : T)
    In(T).new(v)
  end

  class In(U)
    def initialize(@u : U)
    end

    def u
      @u
    end
  end
end

y = Ou(Int32).new.mk(4)
STDERR.puts typeof(y)
STDERR.puts y.u'

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
  printf '%d nested generic namespace case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all nested generic namespace cases passed\n'
