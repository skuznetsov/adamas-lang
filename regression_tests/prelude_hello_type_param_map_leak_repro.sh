#!/usr/bin/env bash
# Prelude hello must compile and print its line.
#
# monomorphize_generic_class/_module bound `T => ...` directly into the
# current `@type_param_map`. Callers save and restore that map by reference,
# so the binding outlived the specialization. Inferring the block-local
# assignment `is_next_ready = @timers.add(event)` in
# Crystal::EventLoop::Polling#add_timer first-instantiated `Timers(Event)`,
# leaked `T => Crystal::EventLoop::Polling::Event`, and hello stopped with
# "receiver repair left bodyless target
# Array(Crystal::DWARF::LineNumbers::Row)#exec_recursive$Symbol_Proc(...)".
# No no-prelude reducer reproduced the leak, so this checks the full prelude.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/prelude-hello.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/hello.cr" <<'CR'
puts "one owner"
CR

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/hello.cr" -o "$WORK_DIR/hello_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/hello_oracle" 5 256 2>/dev/null | grep -v '^\[RUN_SAFE\|^\[EXIT\|^===' || true)"
  if [[ "$oracle_out" != "one owner" ]]; then
    echo "oracle did not print 'one owner': $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/hello.cr" -o "$WORK_DIR/hello" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/hello" ]]; then
  echo "FAIL: prelude hello did not compile" >&2
  grep -v '^\[RUN_SAFE\|^\[EXIT\|^===' "$WORK_DIR/build.log" | tail -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/hello" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | grep -v '^\[RUN_SAFE\|^\[EXIT\|^===' || true)"
if [[ $status -ne 0 || "$printed" != "one owner" ]]; then
  echo "FAIL: prelude hello exit=$status output=$printed" >&2
  exit 1
fi
echo "PASS prelude_hello_type_param_map_leak"
