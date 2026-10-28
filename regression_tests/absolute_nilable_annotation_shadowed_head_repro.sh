#!/usr/bin/env bash
# A root-anchored nilable return annotation such as `: ::File::Error?` must
# keep its `::` anchor when it is turned into the union `::File::Error | Nil`.
# V2 dropped the anchor in three places (the `X?` desugaring, the union
# branch of type lookup, which moved the anchor onto whichever variant sorted
# first, and the canonical variant names re-resolved by union merging), so
# inside `module Sys::File` the variant resolved relative to the enclosing
# module: a phantom `Sys::File::Error`. Stdlib
# `Crystal::System::File.rename : ::File::Error?` is the stage-2 shape:
# `raise error` in `File.rename` found no overload for
# `Crystal::System::File::Error`. The last case checks that a relative
# `File::Error` still resolves to the enclosing module, as in Crystal.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/absolute-nilable-annotation.XXXXXX")"

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

class File
  class Error
    def initialize(@code : Int32)
    end

    def code : Int32
      @code
    end

    def self.build(c : Int32)
      new(c)
    end
  end
end

def take(e : ::File::Error) : Int32
  e.code
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

add_case untyped_param_suffix_if 9 '
module Sys
  module File
    def self.make(a) : ::File::Error?
      ::File::Error.new(a) if a > 0
    end
  end
end

if e = Sys::File.make(9)
  LibC.exit(take(e))
end
LibC.exit(1)'

add_case factory_called_from_shadowed_class 9 '
module Sys
  module File
    def self.make(a, b) : ::File::Error?
      if a > b
        ::File::Error.build(a)
      end
    end
  end
end

class File
  def self.go(a : Int32, b : Int32) : Int32
    if error = Sys::File.make(a, b)
      return take(error)
    end
    0
  end
end

LibC.exit(File.go(9, 1) &+ File.go(1, 9))'

add_case explicit_absolute_union 9 '
module Sys
  module File
    def self.make(a) : ::File::Error | Nil
      ::File::Error.new(a) if a > 0
    end
  end
end

if e = Sys::File.make(9)
  LibC.exit(take(e))
end
LibC.exit(1)'

add_case typed_param_control 9 '
module Sys
  module File
    def self.make(a : Int32) : ::File::Error?
      ::File::Error.new(a) if a > 0
    end
  end
end

if e = Sys::File.make(9)
  LibC.exit(take(e))
end
LibC.exit(1)'

add_case relative_path_resolves_to_enclosing_module 7 '
module Sys
  module File
    class Error
      def code : Int32
        7
      end
    end

    def self.make(a) : File::Error?
      Error.new if a > 0
    end
  end
end

def take(e : Sys::File::Error) : Int32
  e.code
end

if e = Sys::File.make(9)
  LibC.exit(take(e))
end
LibC.exit(1)'

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
  printf '%d absolute nilable annotation case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all absolute nilable annotation cases passed\n'
