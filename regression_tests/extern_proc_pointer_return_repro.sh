#!/usr/bin/env bash
# A lib fun parameter `cb : Void* -> Void*` was converted to a C type by
# peeling the trailing `*` first, producing `Pointer(Proc(Pointer(Void), Void))`.
# The proc arrow binds loosest, so the `*` belongs to the return type. Prelude
# hello on the 1.22.1 stdlib failed on `LibGC.pthread_create`.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/extern-proc-pointer-return.XXXXXX")"
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
  fun pthread_create(t : UInt64*, a : Void*, cb : Void* -> Void*, arg : Void*) : Int32
  fun pthread_join(t : UInt64, r : Void**) : Int32
end

lib LibY
  fun pc = pthread_create(t : UInt64*, a : Void*, cb : Void* -> Void*, arg : Void*) : Int32
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

def raise(msg)
  LibC.exit(90)
end
CR

write_case() {
  local name="$1" body="$2"
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$body"; } > "$WORK_DIR/$name.cr"
}

write_case pointer_return '
cb = ->(p : Void*) { Pointer(Void).new(6_u64) }
t = 0_u64
LibC.pthread_create(pointerof(t), Pointer(Void).new(0_u64), cb, Pointer(Void).new(0_u64))
r = Pointer(Void).new(0_u64)
LibC.pthread_join(t, pointerof(r))
LibC.exit(r.address.to_i32!)'
write_case aliased_fun '
cb = ->(p : Void*) { Pointer(Void).new(7_u64) }
t = 0_u64
LibY.pc(pointerof(t), Pointer(Void).new(0_u64), cb, Pointer(Void).new(0_u64))
r = Pointer(Void).new(0_u64)
LibC.pthread_join(t, pointerof(r))
LibC.exit(r.address.to_i32!)'

CASES=(pointer_return:6 aliased_fun:7)

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
  printf '%d extern proc pointer-return case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'extern proc pointer-return cases passed\n'
