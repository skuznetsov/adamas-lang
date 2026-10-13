#!/usr/bin/env bash
# `def initialize(a, *, r = false)` called as `K.new(40)`. A stage2 compiler
# built by a stage1 with the Array#count split-predicate phi bug miscounted
# the required parameters in the def prefix scan and failed with
# "receiver repair left bodyless target K#initialize$Int32_Bool".
# Run it with a stage2 binary to cover the self-host path. Keep only the
# defaulted call: an explicit `r:` call materializes the body and masks it.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named_only_default_init.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class K
  getter size : Int32
  def initialize(a : Int32, *, r = false)
    @size = r ? a : a + 1
  end
end
LibC.exit(1) unless K.new(40).size == 41
LibC.exit(0)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  grep -E '^\[EXIT' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo named_only_default_initialize_repro_ok
