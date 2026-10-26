#!/usr/bin/env bash
# A non-inlined `&` callee called with blocks of different return types gets a
# late raw-callback target (`H#wrap$..._block__rawcb_<shape>_r<ret>`) whose
# contract states the block proc's ABI. Its `yield` return type was looked up
# by name instead: the `__rawcb_*` suffix stripped to the shared `H#wrap`,
# whose `__block_return__` is whatever another call site recorded last (here
# `TR`). The yield was typed `TR`, so stage 2 stopped with "no overload matches
# finalize_abstract_numeric_return for argument types (..., Nil | TypeRef |
# UInt32)" and smaller programs silently returned the wrong value.
# A block proc returning an enum keeps the enum as its return type.
# Positive cases exit 42 under original Crystal; the negative is rejected by it.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rawcb-late-yield.XXXXXX")"

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

struct TR
  def initialize(@id : UInt32)
  end

  def id : UInt32
    @id
  end
end

class AR
end

class H
  @m = 0

  def initialize(@arena : AR)
  end

  # Several yields: the block is lowered as a raw callback, not inlined.
  def wrap(extra : Int32, &)
    return yield if extra == 0
    old = @m
    return yield if old == extra
    @m = extra
    r = yield
    @m = old
    r
  end

  def a : TR
    wrap(1) { TR.new(3_u32) }
  end

  def seq(d : AR) : UInt32?
    7_u32
  end

  def need(x : UInt32?) : Int32
    x ? 40 : 1
  end
HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

write_case nilable_block_in_branch '
  def b(flag : Bool) : Int32
    last : UInt32? = nil
    if flag
      last = seq(@arena)
    else
      last = wrap(1) do
        seq(@arena)
      end
    end
    need(last)
  end
end

h = H.new(AR.new)
LibC.exit(h.b(false) &+ (h.a.id == 3_u32 ? 2 : 0))'

write_case captured_local_in_branch '
  def b(flag : Bool) : Int32
    last : UInt32? = nil
    if flag
      last = seq(@arena)
    else
      last = wrap(1) do
        d = @arena
        seq(d)
      end
    end
    need(last)
  end
end

h = H.new(AR.new)
LibC.exit(h.b(false) &+ (h.a.id == 3_u32 ? 2 : 0))'

write_case struct_block_lowered_first '
  def b : Int32
    need(wrap(1) { seq(@arena) })
  end
end

h = H.new(AR.new)
t = h.a.id == 3_u32 ? 2 : 0
LibC.exit(h.b &+ t)'

# The block proc of `{ NK::B }` returns the enum, not its Int32 carrier;
# otherwise the late target types the yield as Int32 and is_a?(NK) fails.
write_case enum_block_keeps_identity '
  def e(flag : Bool) : NK?
    return nil unless flag
    wrap(1) { NK::B }
  end
end

enum NK
  A
  B
end

def code(k : NK?) : Int32
  k.is_a?(NK) ? 40 : 1
end

h = H.new(AR.new)
LibC.exit(code(h.e(true)) &+ (h.a.id == 3_u32 ? 2 : 0))'

write_case struct_block_result_rejects '
  def b : Int32
    need(wrap(1) { seq(@arena) }) &+ need(wrap(1) { TR.new(1_u32) })
  end
end

h = H.new(AR.new)
LibC.exit(h.b)'

POSITIVE=(nilable_block_in_branch captured_local_in_branch struct_block_lowered_first
  enum_block_keeps_identity)
NEGATIVE=(struct_block_result_rejects)

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
    printf 'FAIL %s: expected an overload error\n' "$name"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d raw callback late-target yield case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Raw callback late-target yield cases passed\n'
