#!/usr/bin/env bash
# A reference loaded from a field of an owned call-result temp is a borrow of
# that temp. Per-block ARC cleanup rc_dec'd `Info.new(...)` at the end of the
# block that loaded `ab = @abbrevs`, while `ab[0]?` ran in a later block (the
# `(ab = @abbrevs) ? ab[0]? : nil` branch), so Info's destructor had already
# released the Arr and the call read freed memory: the program exited 1
# instead of 42 (shape of Crystal::DWARF::Info#each in dwarf/info.cr). The
# cross-block backward trace now follows FieldGet to its owner.
# All cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/field-borrow-cross-block.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" lookup="$2"
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

class Arr
  def initialize(@v : Int32)
  end

  def []?(i : Int32) : Ab?
    i == 0 ? Ab.new(@v) : nil
  end
end

struct Ab
  def initialize(@t : Int32)
  end

  def tag
    @t
  end
end

class Info
  @abbrevs : Arr?

  def initialize(@abbrevs : Arr?)
  end

  def each(&)
    code = 1
    abbrev = $lookup
    yield code, abbrev
  end
end

r = 0
Info.new(Arr.new(41)).each do |code, abbrev|
  r = abbrev.tag &+ code if abbrev
end
LibC.exit(r)
CR
}

write_case assign_condition_ternary '(ab = @abbrevs) ? ab[code &- 1]? : nil'
# Shape of dwarf/info.cr: `@abbreviations.try &.[code &- 1]?`.
write_case try_shorthand '@abbrevs.try &.[code &- 1]?'
write_case try_block '@abbrevs.try { |a| a[code &- 1]? }'
CASES=(assign_condition_ternary try_shorthand try_block)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${CASES[@]}"; do
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
fi

failures=0

for name in "${CASES[@]}"; do
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

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
