#!/usr/bin/env bash
# An alias declared under `{% if flag?(...) %}` in a module body was
# registered only in the module's method pass, after its nested types. A
# nested module's own macro condition then compared against an unknown name:
# `{% if Limb == UInt64 %}` in Float::FastFloat::Pow5Tables took the UInt32
# branch, and `large_mul(..., LARGE_POWER_OF_5)` found no overload for
# Slice(UInt32) (prelude `"1.5".to_f64?`). Such aliases are now registered in
# source order with the module's other aliases. Each case exits with its
# expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-macro-if-alias-order.XXXXXX")"

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

add_case flag_alias_nested_module 7 '
module FF
  {% if flag?(:bits64) %}
    alias Limb = UInt64
  {% else %}
    alias Limb = UInt32
  {% end %}

  module T
    {% if Limb == UInt64 %}
      V = 7
    {% else %}
      V = 3
    {% end %}
  end
end

LibC.exit(FF::T::V)'

add_case path_module_flag_alias 7 '
module Outer::FF
  {% if flag?(:bits64) %}
    alias Limb = UInt64
  {% else %}
    alias Limb = UInt32
  {% end %}

  module T
    {% if Limb == UInt64 %}
      V = 7
    {% else %}
      V = 3
    {% end %}
  end
end

LibC.exit(Outer::FF::T::V)'

add_case flag_else_alias 7 '
module FF
  {% if flag?(:adamas_no_such_flag) %}
    alias Limb = UInt32
  {% else %}
    alias Limb = UInt64
  {% end %}

  module T
    {% if Limb == UInt64 %}
      V = 7
    {% else %}
      V = 3
    {% end %}
  end
end

LibC.exit(FF::T::V)'

add_case flag_alias_to_later_struct 7 '
module FF
  {% if flag?(:bits64) %}
    alias Box = Inner
  {% end %}

  struct Inner
    def v : Int32
      7
    end
  end
end

LibC.exit(FF::Box.new.v)'

add_case direct_alias_control 7 '
module FF
  alias Limb = UInt64

  module T
    {% if Limb == UInt64 %}
      V = 7
    {% else %}
      V = 3
    {% end %}
  end
end

LibC.exit(FF::T::V)'

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
  printf '%d module macro-if alias order case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all module macro-if alias order cases passed\n'
