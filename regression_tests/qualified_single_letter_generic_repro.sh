#!/usr/bin/env bash
# A single-letter generic class reached through a namespace path, such as
# `Foo::W(Int32)`, must resolve like any other qualified type. V2 scanned the
# name for unresolved one-letter type parameter tokens and treated the `W`
# after `::` as one; since only a top-level `W` exists for that check, the
# lookup returned Void and `Foo::W(Int32).new(1).go` became a call on a
# Pointer. Type parameters are never qualified, so a segment after `::` is
# now skipped. The stage-2 shape is the compiler's own nested generics.
# The `bare_parameter_control` case keeps a real single-letter type
# parameter working. Each case exits with its expected code under original
# Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qualified-single-letter-generic.XXXXXX")"

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
HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

# name:expected-exit
CASES=()

add_case() {
  CASES+=("$1:$2")
  write_case "$1" "$3"
}

add_case namespaced_class 5 '
module Foo
  class W(U)
    def initialize(@i : U)
    end

    def go
      5
    end
  end
end

LibC.exit(Foo::W(Int32).new(1).go)'

add_case two_segment_namespace 6 '
module Foo
  module Bar
    class K(U)
      def initialize(@i : U)
      end

      def go
        @i
      end
    end
  end
end

LibC.exit(Foo::Bar::K(Int32).new(6).go)'

add_case namespaced_restriction 7 '
module Foo
  class W(U)
    def initialize(@i : U)
    end
  end
end

def take(x : Foo::W(Int32))
  7
end

def take(x)
  3
end

LibC.exit(take(Foo::W(Int32).new(1)))'

add_case bare_parameter_control 8 '
class Box(T)
  def initialize(@v : T)
  end

  def get : T
    @v
  end
end

def unwrap(b : Box(T)) forall T
  b.get
end

LibC.exit(unwrap(Box(Int32).new(8)))'

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}" want="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$want" ]]; then
      printf 'ORACLE FAIL: original %s exited %s, not %s\n' "$name" \
        "$(exit_code_of "$WORK_DIR/$name.orig.run")" "$want" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}" want="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s: compile failed\n' "$name" >&2
    grep -v '^\[RUN_SAFE' "$log" | grep -m3 -i 'error\|overload' >&2 || tail -5 "$log" >&2
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  got="$(exit_code_of "$run_log")"
  if [[ "$got" == "$want" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: exit %s, expected %s\n' "$name" "$got" "$want" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d qualified single-letter generic case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all qualified single-letter generic cases passed\n'
