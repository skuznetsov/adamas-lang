#!/usr/bin/env bash
# `Array(T)#[]?(index : Int)` comes from the included `Indexable(T)`, while
# Array itself declares the siblings `[]?(range : Range) : Array(T)?` and
# `[]?(start : Int, count : Int) : Array(T)?`. Return-type lookups answered an
# Int32 call through the class family name, whose arity-only lookup picked a
# class sibling: `abbrev = @abbreviations.try &.[code &- 1]?` in
# Crystal::DWARF::Info was typed `Array(Abbrev)?` and every prelude program
# failed in dwarf.cr. The family name now answers only while it resolves to
# the selected source definition, and inference for explicit receivers and
# `&.` shorthand selects the included-module overload by argument types.
# A method the element lacks stays rejected. Positive cases exit 42 under
# original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/included-module-overload-return.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" main="$2"
  cat > "$WORK_DIR/$name.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Object
  def try(&)
    yield self
  end
end

struct Nil
  def try(&)
    self
  end
end

module Indexable(T)
  def []?(index : Int)
    index == 0 ? fetch : nil
  end
end

struct Range(B, E)
end

class Arr(T)
  include Indexable(T)

  def initialize(@v : T)
  end

  def fetch : T
    @v
  end

  def []?(range : Range) : Arr(T)?
    nil
  end

  def []?(start : Int, count : Int) : Arr(T)?
    nil
  end
end

struct Ab
  def initialize(@t : Int32)
  end

  def tag
    @t
  end
end

# Shape of Crystal::DWARF::Info#each.
class Info
  @abbreviations : Arr(Ab)?

  def initialize(@abbreviations : Arr(Ab)?)
  end

  def first(code)
    if abbrev = @abbreviations.try &.[code &- 1]?
      abbrev.tag &+ 1
    else
      0
    end
  end

  def each_u32(&)
    code = 1_u32
    if abbrev = @abbreviations.try &.[code &- 1]?
      yield code, abbrev
    else
      yield code, nil
    end
  end

  def each_i32(&)
    code = 1
    if abbrev = @abbreviations.try &.[code &- 1]?
      yield code, abbrev
    else
      yield code, nil
    end
  end
end

def each_pair(a : Arr(Ab), &)
  yield 1, a[0]?
end

a = Arr(Ab).new(Ab.new(41))
r = 0
$main
LibC.exit(r)
CR
}

write_case explicit_receiver_local 'x = a[0]?
r = x.tag &+ 1 if x'
write_case yield_argument 'each_pair(a) do |code, x|
  r = x.tag &+ code if x
end'
write_case try_shorthand_ivar_int32 'r = Info.new(a).first(1)'
write_case try_shorthand_ivar_uint32 'r = Info.new(a).first(1_u32)'
write_case try_shorthand_yield_uint32 'Info.new(a).each_u32 do |code, abbrev|
  r = abbrev.tag &+ (code == 1 ? 1 : 0) if abbrev
end'
write_case try_shorthand_yield_int32 'Info.new(a).each_i32 do |code, abbrev|
  r = abbrev.tag &+ (code == 1 ? 1 : 0) if abbrev
end'
write_case try_shorthand_local 'if x = a.try &.[0]?
  r = x.tag &+ 1
end'
# Control: an explicit block already selected the included overload.
write_case try_block_control 'if x = a.try { |arr| arr[0]? }
  r = x.tag &+ 1
end'
# Negative: Ab declares no missing method.
write_case element_missing_method_rejected 'x = a[0]?
r = x.missing if x'

POSITIVE=(explicit_receiver_local yield_argument try_shorthand_ivar_int32 try_shorthand_ivar_uint32 try_shorthand_yield_uint32 try_shorthand_yield_int32 try_shorthand_local try_block_control)
NEGATIVE=(element_missing_method_rejected)

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
