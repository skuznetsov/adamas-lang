#!/usr/bin/env bash
# `f(a, *args, **opts)` forwarding lost the splat: the `**opts` parameter was
# counted as a trailing positional, so `fwd(2, 40)` packed nothing (or bound the
# last positional to `opts`), and `take(*args, **opts)` passed an empty
# `**opts` as one more positional argument. `Reference.unsafe_construct` uses
# exactly this shape (1.22.1 `Sync::Mutex` via `ReferenceStorage`).
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/double-splat-forward.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib LibC
  fun exit(status : Int32) : NoReturn
  fun malloc(size : UInt64) : Void*
  fun realloc(ptr : Void*, size : UInt64) : Void*
  fun free(ptr : Void*)
end

fun __crystal_malloc64(size : UInt64) : Void*
  LibC.malloc(size)
end

fun __crystal_malloc_atomic64(size : UInt64) : Void*
  LibC.malloc(size)
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end
CR

write_case() {
  local name="$1" body="$2"
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$body"; } > "$WORK_DIR/$name.cr"
}

write_case splat_then_empty_double_splat '
def take(k : Int32) : Int32
  k
end

def fwd(a : Int32, *args, **opts) : Int32
  take(*args, **opts) + a
end

LibC.exit(fwd(2, 40))'

write_case class_method_new_forwarding '
class Mx
  def initialize(@k : Int32)
  end

  def k : Int32
    @k
  end

  def self.make(a : Int32, *args, **opts) : self
    obj = new(*args, **opts)
    obj
  end
end

LibC.exit(Mx.make(2, 40).k)'

write_case two_positionals_through_splat '
def take(k : Int32, j : Int32) : Int32
  k + j
end

def fwd(a : Int32, *args, **opts) : Int32
  take(*args, **opts) + a
end

LibC.exit(fwd(2, 30, 10))'

CASES=(splat_then_empty_double_splat:42 class_method_new_forwarding:40 two_positionals_through_splat:42)

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
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
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
  printf '%d double-splat forwarding case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'double-splat forwarding cases passed\n'
