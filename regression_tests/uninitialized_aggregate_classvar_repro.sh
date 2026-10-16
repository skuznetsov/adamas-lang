#!/usr/bin/env bash
# Uninitialized aggregate class variables need backing storage in both init modes.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/uninitialized-classvar.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    printf 'kept_tmp=%s\n' "$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib UninitProbeC
  fun putchar(value : Int32) : Int32
end

class AggregateClassVarProbe
  @@slots = uninitialized UInt64[2]

  def self.write_and_read(a : UInt64, b : UInt64) : Bool
    @@slots[0] = a
    @@slots[1] = b
    @@slots[0] == a && @@slots[1] == b
  end
end

class DeclaredAggregateClassVarProbe
  @@slots : UInt64[2]
  @@slots = uninitialized UInt64[2]

  def self.write_and_read(a : UInt64, b : UInt64) : Bool
    @@slots[0] = a
    @@slots[1] = b
    @@slots[0] == a && @@slots[1] == b
  end
end

def local_aggregate(a : UInt64, b : UInt64) : Bool
  slots = uninitialized UInt64[2]
  slots[0] = a
  slots[1] = b
  slots[0] == a && slots[1] == b
end

a = 0x1234567887654321_u64
b = 0xfedcba9876543210_u64
UninitProbeC.putchar(local_aggregate(a, b) ? 76 : 70)
UninitProbeC.putchar(AggregateClassVarProbe.write_and_read(a, b) ? 65 : 70)
UninitProbeC.putchar(DeclaredAggregateClassVarProbe.write_and_read(a, b) ? 68 : 70)
UninitProbeC.putchar(AggregateClassVarProbe.write_and_read(b, a) ? 82 : 70)
UninitProbeC.putchar(10)
CRYSTAL

for mode in lazy eager; do
  init_env=(-u ADAMAS_EAGER_CLASSVAR_INIT)
  if [[ "$mode" == eager ]]; then
    init_env=(ADAMAS_EAGER_CLASSVAR_INIT=1)
  fi
  if ! env "${init_env[@]}" ADAMAS_LLVM_CACHE=0 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode.build.resources.json" \
    "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 "$WORK_DIR/probe.cr" \
    --no-prelude --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/$mode" \
    >"$WORK_DIR/$mode.build.log" 2>&1; then
    cat "$WORK_DIR/$mode.build.log" >&2
    exit 1
  fi
  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode.run.resources.json" \
    "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$mode" 5 512 \
    >"$WORK_DIR/$mode.run.log" 2>&1; then
    cat "$WORK_DIR/$mode.run.log" >&2
    exit 1
  fi
  actual="$(sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/{/^=== STDOUT ===$/d;/^=== STDERR ===$/d;p;}' "$WORK_DIR/$mode.run.log")"
  if [[ "$actual" != 'LADR' ]] || ! grep -Fq '[EXIT: 0]' "$WORK_DIR/$mode.run.log"; then
    cat "$WORK_DIR/$mode.run.log" >&2
    printf 'uninitialized aggregate storage failed in %s mode\n' "$mode" >&2
    exit 1
  fi
done
printf 'PASS: local, inferred and declared aggregate classvars in lazy/eager init\n'
