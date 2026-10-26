#!/usr/bin/env bash
# A method of a generic module reached through `extend M(self)` or
# `include M(X)` keeps the module's bindings (`D => Owner`) in its function
# type-param map, but overload lookup checked its restriction in the
# non-generic owner's context. A path through the module param
# (`u : D::CarrierUInt`, `u : D::Box`) never resolved there, so the only
# candidate was rejected. Stage 2 failed in float/printer/dragonbox.cr with
# "no overload matches Float::Printer::Dragonbox::ImplInfo_Float64.extract_exponent_bits
# for argument types (UInt64)". An argument that contradicts the bound
# restriction must stay rejected.
# Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-param-path.XXXXXX")"

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

module Methods(D)
  def ext(u : D::CarrierUInt)
    u.to_i32! &+ D::BIAS
  end

  def unbox(b : D::Box)
    b.v &+ D::BIAS
  end
end

module Info64
  extend Methods(self)

  BIAS = 2
  alias CarrierUInt = UInt64

  class Box
    def initialize(@v : Int32); end

    def v
      @v
    end
  end
end

module Info32
  extend Methods(Info32)

  BIAS = 20
  alias CarrierUInt = UInt32

  class Box
    def initialize(@v : Int32); end

    def v
      @v
    end
  end
end

class Holder
  include Methods(Holder)

  BIAS = 32
  alias CarrierUInt = UInt64

  class Box
    def initialize(@v : Int32); end

    def v
      @v
    end
  end
end

HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

write_case extend_self_alias "LibC.exit(Info64.ext(40_u64))"
write_case extend_explicit_alias "LibC.exit(Info32.ext(22_u32))"
write_case two_extenders "LibC.exit(Info64.ext(10_u64) &+ Info32.ext(10_u32))"
write_case extend_nested_class "LibC.exit(Info64.unbox(Info64::Box.new(40)))"
write_case include_alias "LibC.exit(Holder.new.ext(10_u64))"
write_case include_nested_class "LibC.exit(Holder.new.unbox(Holder::Box.new(10)))"
# Negative: Info64's carrier is UInt64. (Original Crystal accepts a UInt32
# variable here through lossless number autocast, so use a Char.)
write_case wrong_carrier_rejected "LibC.exit(Info64.ext('a'))"
# Negative: Info64::Box is not Info32::Box.
write_case wrong_box_rejected "LibC.exit(Info32.unbox(Info64::Box.new(10)))"

POSITIVE=(extend_self_alias extend_explicit_alias two_extenders extend_nested_class include_alias
  include_nested_class)
NEGATIVE=(wrong_carrier_rejected wrong_box_rejected)

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
  printf '%d module param path restriction case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Module param path restriction cases passed\n'
