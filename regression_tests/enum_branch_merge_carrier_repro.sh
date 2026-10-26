#!/usr/bin/env bash
# Enum values are lowered through their base-integer carrier and keep their
# enum identity in a side table. A merge of if/else or case branches that all yield
# the same enum must keep that identity, or a later `mode: m` argument is
# typed Int32 and rejected. Stage 2 failed in cli.cr's memory_config_for with
# "no overload matches Adamas::HIR::MemoryConfig#initialize for argument
# types (Int32, UInt32)". A ternary merge already kept it. Merges of an enum
# with an integer, or of two different enums, must stay rejected.
# Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum-branch-merge.XXXXXX")"

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

# No prelude: case/when needs Int32#===.
struct Int32
  def ===(other : Int32)
    self == other
  end
end

module H
  struct Cfg
    @thr : UInt32
    @mode : Mode

    enum Mode
      A
      B
      C
    end

    enum Other
      X
      Y
      Z
    end

    def initialize(
      @thr : UInt32 = 4096_u32,
      @mode : Mode = Mode::B
    )
    end

    def thr
      @thr
    end

    def mode
      @mode
    end
  end
end

def pick(i : Int32)
$body
  H::Cfg.new(thr: 40_u32, mode: m)
end

d = pick(2)
m = d.mode
LibC.exit(d.thr.to_i32! &+ pointerof(m).as(Int32*).value)
CR
}

write_case if_else "  m = if i == 2
        H::Cfg::Mode::C
      else
        H::Cfg::Mode::B
      end"
write_case if_elsif_else "  m = if i == 0
        H::Cfg::Mode::A
      elsif i == 2
        H::Cfg::Mode::C
      else
        H::Cfg::Mode::B
      end"
write_case nested_if "  m = if i == 0
        H::Cfg::Mode::A
      else
        if i == 2
          H::Cfg::Mode::C
        else
          H::Cfg::Mode::B
        end
      end"
# case/when merges carry the same identity.
write_case case_when "  m = case i
      when 0 then H::Cfg::Mode::A
      when 2 then H::Cfg::Mode::C
      else
        H::Cfg::Mode::B
      end"
# Control: the ternary merge already worked.
write_case ternary "  m = i == 2 ? H::Cfg::Mode::C : H::Cfg::Mode::A"
# Negative: Mode | Int32 is not a Mode.
write_case enum_int_rejected "  m = if i == 2
        H::Cfg::Mode::C
      else
        5
      end"
# Negative: a case merge of Mode and Int32 is not a Mode.
write_case case_enum_int_rejected "  m = case i
      when 2 then H::Cfg::Mode::C
      else
        5
      end"
# Negative: Mode | Other is not a Mode.
write_case two_enums_rejected "  m = if i == 2
        H::Cfg::Mode::C
      else
        H::Cfg::Other::Y
      end"

POSITIVE=(if_else if_elsif_else nested_if case_when ternary)
NEGATIVE=(enum_int_rejected case_enum_int_rejected two_enums_rejected)

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
    printf 'FAIL %s: expected a no overload matches error\n' "$name"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d enum branch merge case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Enum branch merge cases passed\n'
