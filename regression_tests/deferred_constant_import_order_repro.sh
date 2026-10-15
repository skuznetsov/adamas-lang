#!/usr/bin/env bash
# Required constants must initialize before later files call their readers.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:?usage: deferred_constant_import_order_repro.sh <candidate-compiler>}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/deferred-constant-import-order.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_work=$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/provider.cr" <<'CRYSTAL'
module ImportedConstantProvider
  def self.read : Int32
    VALUES[0]
  end




















  VALUES = {42}
end
CRYSTAL
cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
require "./provider"
module ImportedConstantConsumer
  VALUE = ImportedConstantProvider.read
end
module ForwardIndexedConstant
  FIRST = SECOND[0]
  SECOND = {7}
end
puts ImportedConstantConsumer::VALUE
puts ImportedConstantProvider::VALUES[0]
puts ForwardIndexedConstant::FIRST
CRYSTAL
cat >"$WORK_DIR/expected.stdout" <<'EXPECTED'
42
42
7
EXPECTED

for mode in original candidate; do
  mkdir -p "$WORK_DIR/$mode.cache"
  if [[ "$mode" == original ]]; then
    command=("$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" 180 8192 build
      "$WORK_DIR/probe.cr" --no-debug --link-flags=-fuse-ld=/usr/bin/ld)
  else
    command=("$SAFE_RUNNER" "$COMPILER" 180 8192
      "$WORK_DIR/probe.cr" --no-debug --no-ast-cache --no-llvm-cache)
  fi
  if ! CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/$mode.cache" \
    ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
    "${command[@]}" -o "$WORK_DIR/$mode.bin" >"$WORK_DIR/$mode-build.log" 2>&1; then
    cat "$WORK_DIR/$mode-build.log" >&2
    exit 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/$mode.bin" 10 512 \
    >"$WORK_DIR/$mode.stdout" 2>"$WORK_DIR/$mode-run.log"; then
    cat "$WORK_DIR/$mode-run.log" >&2
    exit 1
  fi
  diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/$mode.stdout"
done
echo "ok: imported and indexed constant initializers match original Crystal"
