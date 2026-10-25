#!/usr/bin/env bash
# `SystemError`'s `macro included` runs `extend ::SystemError::ClassMethods`.
# The extend target keeps its `::` prefix while module bodies are keyed without
# it, so no class methods were attached and every 1.22.1 prelude program failed
# with "undefined method 'from_os_error' for File::Error".
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/absolute-extend.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

module SysErr
  macro included
    extend ::SysErr::ClassMethods
  end

  module ClassMethods
    def from_os_error(message : String?, code : Int32, **opts)
      self.new_from_os_error(message, code, **opts)
    end

    protected def new_from_os_error(message : String?, code, **opts)
      self.new(message, **opts)
    end
  end
end

class Err
  def initialize(@message : String?)
    @code = 1
  end

  def code : Int32
    @code
  end
end

class IOErr < Err
  include SysErr

  def initialize(message : String?, *, @target : String? = nil)
    super(message)
  end
end
CR

write_case() {
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$2"; } > "$WORK_DIR/$1.cr"
}

write_case direct_includer '
LibC.exit(IOErr.from_os_error("x", 2, target: "f").code + 41)'

write_case subclass_of_includer '
class FErr < IOErr
end

LibC.exit(FErr.from_os_error("x", 2, target: "f").code + 41)'

write_case namespaced_includer '
module Outer
  class NErr < Err
    include ::SysErr
  end
end

LibC.exit(Outer::NErr.from_os_error("x", 2).code + 41)'

CASES=(direct_includer:42 subclass_of_includer:42 namespaced_includer:42)

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
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d absolute extend case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'absolute extend cases passed\n'
