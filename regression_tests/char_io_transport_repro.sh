#!/usr/bin/env bash
# Char#to_s(IO) must preserve exact bytes on the direct UTF-8 write branch.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/char_io_transport.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/probe.cr" <<'CR'
require "c/unistd"
built = String.build do |io|
  io << '0'
  io << '1'
  io << 'A'
  io << '(' << 'T' << ')'
end
LibC.write(1, built.to_unsafe.as(Void*), built.bytesize)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
  "$WORK_DIR/probe.cr" -o "$WORK_DIR/probe" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/probe" 5 512 \
  >"$WORK_DIR/output" 2>"$WORK_DIR/run.log"; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
# Compare raw child output, including punctuation used by generic names.
if ! python3 - "$WORK_DIR/output" <<'PY'
import pathlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
if data != b'01A(T)':
    sys.stderr.buffer.write(data)
    raise SystemExit('FAIL: Char transport did not preserve 01A(T)')
PY
then
  exit 1
fi
echo char_io_transport_repro_ok
