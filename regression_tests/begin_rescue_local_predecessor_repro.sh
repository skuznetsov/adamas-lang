#!/usr/bin/env bash
# A protected body may finish in an inner branch's join, rather than its entry.
# Both local merges (direct continuation and ensure) must use that actual edge.
# This qualifies normal flow only; it deliberately does not throw an exception.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/begin-rescue-local-predecessor.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL" ]] || exit 2

cat >"$WORK/probe.cr" <<'CRYSTAL'
lib LibC
  fun _exit(status : Int32) : NoReturn
end

# The original empty-prelude backend needs these symbols even on normal flow.
# Every unexpected raise fails; no fake handler can make a thrown case pass.
fun __crystal_personality(version : Int32, actions : Int32, cls : UInt64, ex : Void*, ctx : Void*) : Int32
  0
end
fun __crystal_get_exception(ex : Void*) : UInt64
  0_u64
end
fun __crystal_raise(ex : Void*) : NoReturn
  LibC._exit(98)
end
fun __crystal_raise_overflow : NoReturn
  LibC._exit(99)
end

def direct_merge(flag : Bool) : Int32
  value = 11
  begin
    if flag
      value = 73
    else
      value = 29
    end
  rescue
    value = 41
  end
  value
end

def ensure_merge(flag : Bool) : Int32
  value = 11
  begin
    if flag
      value = 73
    else
      value = 29
    end
  rescue
    value = 41
  ensure
    value = value + 5
  end
  value
end

LibC._exit(1) unless direct_merge(true) == 73
LibC._exit(2) unless direct_merge(false) == 29
LibC._exit(3) unless ensure_merge(true) == 78
LibC._exit(4) unless ensure_merge(false) == 34
LibC._exit(42)
CRYSTAL

for producer in original adamas; do
  if [[ "$producer" == original ]]; then
    "$SAFE_RUNNER" "$ORIGINAL" 120 4096 build "$WORK/probe.cr" --prelude=empty \
      --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK/$producer" >"$WORK/$producer.compile.log" 2>&1
  else
    "$SAFE_RUNNER" "$COMPILER" 120 4096 "$WORK/probe.cr" --no-prelude \
      --no-ast-cache --no-llvm-cache -o "$WORK/$producer" >"$WORK/$producer.compile.log" 2>&1
  fi
  status=0
  "$SAFE_RUNNER" "$WORK/$producer" 5 512 >"$WORK/$producer.run.log" 2>&1 || status=$?
  if [[ "$status" != 42 ]] || ! grep -q '^\[EXIT: 42\]' "$WORK/$producer.run.log"; then
    cat "$WORK/$producer.run.log" >&2
    echo "FAIL[$producer]: expected all four branch results and exit 42" >&2
    exit 1
  fi
  echo "PASS[$producer]: both branch arms with direct and ensure local merges"
done
