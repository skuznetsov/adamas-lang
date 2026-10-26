#!/usr/bin/env bash
# The return type of a non-inlined `&` block is inferred before the block is
# lowered, from the typeof-locals map. That map holds a local's assigned type
# (`body = node.body` -> `Nil | BD`), while `if body = ...`, `if x` and
# `is_a?` narrow only the lowering context. `wrap(1) { seq(body) }` found no
# `seq(Nil | BD)` overload, left the block return unnamed, and the call went to
# the shared `H#wrap$..._block` target whose yield is typed by another call
# site (`TR`). Stage 2 stopped with "no overload matches
# finalize_abstract_numeric_return for argument types (..., Nil | TypeRef |
# UInt32)" in `lower_def`.
# Positive cases exit 42 under original Crystal; negatives are rejected by it.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/narrowed-capture-block.XXXXXX")"

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

class BD
end

class AR
end

class DN
  def initialize(@body : BD?)
  end

  def body : BD?
    @body
  end
end

class H
  @m = 0

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

  def seq(b : BD) : UInt32?
    7_u32
  end

  def need(x : UInt32?) : Int32
    x ? 40 : 1
  end
HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

write_case assign_condition_narrowed '
  def b(node : DN) : Int32
    last_value : UInt32? = nil
    if body = node.body
      last_value = wrap(1) do
        seq(body)
      end
    end
    need(last_value)
  end
end

h = H.new
t = h.a.id == 3_u32 ? 2 : 0
LibC.exit(h.b(DN.new(BD.new)) &+ t)'

write_case truthy_local_narrowed '
  def b(flag : Bool) : Int32
    body = flag ? BD.new : nil
    last_value : UInt32? = nil
    if body
      last_value = wrap(1) { seq(body) }
    end
    need(last_value)
  end
end

h = H.new
t = h.a.id == 3_u32 ? 2 : 0
LibC.exit(h.b(true) &+ t)'

write_case is_a_narrowed '
  def b(flag : Bool) : Int32
    x = flag ? BD.new : AR.new
    last_value : UInt32? = nil
    if x.is_a?(BD)
      last_value = wrap(1) { seq(x) }
    end
    need(last_value)
  end
end

h = H.new
t = h.a.id == 3_u32 ? 2 : 0
LibC.exit(h.b(true) &+ t)'

write_case unnarrowed_local_rejects '
  def b(node : DN) : Int32
    body = node.body
    need(wrap(1) { seq(body) })
  end
end

h = H.new
LibC.exit(h.b(DN.new(BD.new)) &+ (h.a.id == 3_u32 ? 2 : 0))'

# A write inside the block widens the local for the whole block body: the
# outer narrowing must not be borrowed for it.
write_case reassigned_in_block_rejects '
  def b(node : DN) : Int32
    last_value : UInt32? = nil
    if body = node.body
      last_value = wrap(1) do
        r = seq(body)
        body = nil
        r
      end
    end
    need(last_value)
  end
end

h = H.new
LibC.exit(h.b(DN.new(BD.new)) &+ (h.a.id == 3_u32 ? 2 : 0))'

POSITIVE=(assign_condition_narrowed truthy_local_narrowed is_a_narrowed)
NEGATIVE=(unnarrowed_local_rejects reassigned_in_block_rejects)

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
  printf '%d narrowed-capture block return case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Narrowed-capture block return cases passed\n'
