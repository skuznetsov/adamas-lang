#!/usr/bin/env bash
# Writes through pointerof(local) must be visible to later reads of that local.
# The compiler previously reused stale SSA after materializing the pointerof
# alloca. Keep an ordinary read and a nonconstant scalar write in the same
# guard so the backend's generic addressable reload is exercised.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/pointerof_writeback.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

cat >"$WORKDIR/probe.cr" <<'CR'
lib LibC
  fun strtol(text : UInt8*, end_ptr : UInt8**, base : Int32) : Int64
  fun getpid : Int32
  fun memset(buffer : Void*, value : Int32, size : UInt64) : Void*
  fun getpid : Int32
  fun memset(buffer : Void*, value : Int32, size : UInt64) : Void*
  fun exit(status : Int32) : NoReturn
end

def pointerof_external_writeback_status : Int32
  text = "42"
  end_ptr = Pointer(UInt8).null
  LibC.strtol(text.to_unsafe, pointerof(end_ptr), 10)
  return 1 if end_ptr.null?
  return 2 unless end_ptr.value == 0_u8
  0
end

def pointerof_scalar_writeback_status : Int32
  value = LibC.getpid
  LibC.memset(pointerof(value).as(Void*), 42, 4_u64)
  return 1 unless value == 707406378
  0
end

def pointerof_read_control_status : Int32
  value = Pointer(UInt8).null
  slot = pointerof(value)
  return 1 if slot.null?
  return 2 unless value.null?
  0
end

LibC.exit(
  pointerof_external_writeback_status != 0 ? 1 :
    (pointerof_scalar_writeback_status != 0 ? 2 : pointerof_read_control_status)
)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 \
  "$WORKDIR/probe.cr" --no-prelude -o "$WORKDIR/probe" \
  >"$WORKDIR/compile.log" 2>&1; then
  echo "FAIL: Adamas compilation" >&2
  cat "$WORKDIR/compile.log" >&2
  exit 1
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORKDIR/probe" 5 512 \
  >"$WORKDIR/run.log" 2>&1; then
  echo "FAIL: compiled pointerof probe" >&2
  cat "$WORKDIR/run.log" >&2
  exit 1
fi
echo 'PASS: pointerof external writeback'
