#!/usr/bin/env bash
# Receiver specialization qualified every `Entry(` of a return type with the
# receiver's nested Entry (a Hash::Entry shortcut). `\bEntry\(` also matched
# after `::`, so the element type `Arena::Entry(T)` of a receiver declaring its
# own Entry became the phantom `Arena::Box::Entry(T)`. In the prelude,
# `Slice(Pointer(Arena::Entry(T)))#each` produced
# `Pointer(Arena::Slice::Entry(T))` and hello failed in its `#to_s` with
# "undefined constant T". The HIR check keeps the phantom type out even when
# the run result survives.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/receiver-nested-entry.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end
CR

write_case() {
  local name="$1" body="$2"
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$body"; } > "$WORK_DIR/$name.cr"
}

write_case qualified_entry_element '
module Ns
  class Arena(T)
    class Entry(T)
      def initialize(@v : T)
      end

      def v : T
        @v
      end
    end
  end
end

module Idx(T)
  def each(&)
    i = 0
    while i < 1
      yield unsafe_fetch(i)
      i = 1
    end
  end
end

class Box(T)
  include Idx(T)

  class Entry(U)
  end

  def initialize(@x : T)
  end

  def unsafe_fetch(i : Int32) : T
    @x
  end
end

b = Box(Ns::Arena::Entry(Int32)).new(Ns::Arena::Entry(Int32).new(5))
r = 0
b.each { |e| r = e.v }
LibC.exit(r)'

CASES=(qualified_entry_element:5)

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
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
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

hir_log="$WORK_DIR/hir.log"
"$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty --emit hir \
  "$WORK_DIR/qualified_entry_element.cr" -o "$WORK_DIR/hir_out" > "$hir_log" 2>&1 || true
if [[ ! -f "$WORK_DIR/hir_out.hir" ]]; then
  printf 'FAIL hir: no HIR emitted\n'
  failures=$((failures + 1))
elif grep -q 'Arena::Box::Entry' "$WORK_DIR/hir_out.hir"; then
  printf 'FAIL hir: phantom %s\n' "$(grep -m1 'Arena::Box::Entry' "$WORK_DIR/hir_out.hir")"
  failures=$((failures + 1))
else
  printf 'PASS hir\n'
fi

if [[ "$failures" -ne 0 ]]; then
  printf '%d receiver nested Entry case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'receiver nested Entry cases passed\n'
