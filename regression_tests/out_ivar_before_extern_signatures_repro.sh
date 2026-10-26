#!/usr/bin/env bash
# `out @ivar` passed to a lib fun declares the ivar with the parameter's
# pointee type. Class layout is computed while classes are registered, but
# extern signatures are registered only after that source type pass, so the
# implicit-ivar scan could not see the fun and dropped the ivar. The object
# was allocated without it, `out @m` wrote into a temporary, and
# `pointerof(@m)` pointed outside the object: prelude hello raised from
# Thread::Mutex#lock during scheduler start. Positive cases exit 42 under
# original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/out-ivar-extern.XXXXXX")"

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

  struct PM
    sig : Int64
    o1 : Int64
    o2 : Int64
    o3 : Int64
    o4 : Int64
    o5 : Int64
    o6 : Int64
    o7 : Int64
  end

  fun pthread_mutex_init(m : PM*, attr : Void*) : Int32
  fun pthread_mutex_lock(m : PM*) : Int32
  fun pthread_mutex_unlock(m : PM*) : Int32
  fun posix_memalign(p : Void**, alignment : UInt64, size : UInt64) : Int32
end
HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

# Thread::Mutex's shape: the result goes to a local.
write_case local_assign 'class Mu
  def initialize
    @tag = 42
    ret = LibC.pthread_mutex_init(out @m, nil)
    @tag = 3 unless ret == 0
  end

  def run : Int32
    return 3 unless LibC.pthread_mutex_lock(pointerof(@m)) == 0
    return 3 unless LibC.pthread_mutex_unlock(pointerof(@m)) == 0
    @tag
  end
end

LibC.exit(Mu.new.run)'
write_case ivar_assign 'class Mu
  def initialize
    @init = LibC.pthread_mutex_init(out @m, nil)
  end

  def run : Int32
    return 3 unless @init == 0
    LibC.pthread_mutex_lock(pointerof(@m)) == 0 ? 42 : 3
  end
end

LibC.exit(Mu.new.run)'
write_case statement 'class Mu
  def initialize
    LibC.pthread_mutex_init(out @m, nil)
    @after = 42
  end

  def run : Int32
    return 3 unless LibC.pthread_mutex_lock(pointerof(@m)) == 0
    @after
  end
end

LibC.exit(Mu.new.run)'
# A pointer pointee: the ivar is Void*, written by the C function.
write_case pointer_pointee 'class Buf
  def initialize
    @rc = LibC.posix_memalign(out @p, 16_u64, 64_u64)
    @after = 42
  end

  def run : Int32
    return 3 unless @rc == 0
    @p ? @after : 3
  end
end

LibC.exit(Buf.new.run)'

POSITIVE=(local_assign ivar_assign statement pointer_pointee)

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

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
