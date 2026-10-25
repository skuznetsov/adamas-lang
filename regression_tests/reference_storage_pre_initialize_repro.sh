#!/usr/bin/env bash
# `ReferenceStorage(T)` was an empty struct and `pre_initialize` had no
# lowering: `Mx.unsafe_construct(pointerof(@lock), k)` (1.22.1
# `Sync::Exclusive`/`Sync::Shared` mutex storage) returned Nil, and the ivar
# `@lock` was a carrier pointer, so `pointerof(@lock)` and `@lock.to_reference`
# named different bytes. ReferenceStorage(T) now has T's instance size and is
# inline; `pre_initialize` zeroes, runs ivar initializers and stamps the type id.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reference-storage.XXXXXX")"
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

@[Primitive(:ReferenceStorageType)]
struct ReferenceStorage(T) < Value
  private def initialize
  end

  def to_reference : T
    pointerof(@type_id).as(T)
  end
end

class Reference
  @[Primitive(:pre_initialize)]
  def self.pre_initialize(address : Pointer)
    {% @type %}
  end

  def self.unsafe_construct(address : Pointer, *args, **opts) : self
    obj = pre_initialize(address)
    obj.initialize(*args, **opts)
    obj
  end
end
CR

write_case() {
  local name="$1" body="$2"
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$body"; } > "$WORK_DIR/$name.cr"
}

write_case ivar_storage_construct '
class Mx
  @n = 7

  def initialize(@k : Int32)
  end

  def sum : Int32
    @n + @k
  end
end

class Holder
  @lock = uninitialized ReferenceStorage(Mx)

  def initialize(k : Int32)
    @lock = uninitialized ReferenceStorage(Mx)
    Mx.unsafe_construct(pointerof(@lock), k)
  end

  def lock : Mx
    @lock.to_reference
  end
end

LibC.exit(Holder.new(44).lock.sum)'

write_case local_storage_construct '
class Mx
  @n = 7

  def initialize(@k : Int32)
  end

  def sum : Int32
    @n + @k
  end
end

buf = uninitialized ReferenceStorage(Mx)
m = Mx.unsafe_construct(pointerof(buf), 40)
LibC.exit(m.sum + buf.to_reference.sum + 4)'

write_case local_storage_same_address '
class Mx
  @n = 7

  def initialize(@k : Int32)
  end
end

buf = uninitialized ReferenceStorage(Mx)
a = pointerof(buf).as(Void*).address
b = buf.to_reference.as(Void*).address
LibC.exit(a == b ? 42 : 13)'

write_case ivar_storage_same_address '
class Mx
  @n = 7

  def initialize(@k : Int32)
  end
end

class Holder
  @pad = 1
  @lock = uninitialized ReferenceStorage(Mx)

  def same? : Bool
    pointerof(@lock).as(Void*).address == @lock.to_reference.as(Void*).address
  end
end

LibC.exit(Holder.new.same? ? 42 : 13)'

CASES=(ivar_storage_construct:51 local_storage_construct:98 local_storage_same_address:42 ivar_storage_same_address:42)

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
  printf '%d ReferenceStorage case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'ReferenceStorage cases passed\n'
