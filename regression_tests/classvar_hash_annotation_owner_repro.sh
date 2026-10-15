#!/usr/bin/env bash
# Hash class-variable annotations keep canonical type identity across nested owners.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN_OVERRIDE:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
KEEP="${KEEP_ARTIFACTS:-0}"

[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -x "$SAFE_RUNNER" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "usage: $0 <candidate-compiler>" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/classvar-hash-annotation-owner.XXXXXX")"
cleanup() {
  local result=$?
  for cache in "$WORK_DIR"/*-cache; do
    [[ -d "$cache" ]] && rm -rf "$cache"
  done
  if [[ "$result" -ne 0 || "$KEEP" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
module Crystal::System::Signal
  alias ExplicitHandler = ::Signal -> Nil

  @@handler_alias = {} of ::Signal => Handler
  @@direct_proc = {} of ::Signal => Proc(::Signal, Nil)
  @@explicit_alias = {} of ::Signal => ExplicitHandler

  def self.store_handler(signal : ::Signal, handler : Handler) : Bool
    @@handler_alias[signal] = handler
    !@@handler_alias[signal]?.nil?
  end

  def self.store_direct(signal : ::Signal, handler : Proc(::Signal, Nil)) : Bool
    @@direct_proc[signal] = handler
    !@@direct_proc[signal]?.nil?
  end

  def self.store_explicit_alias(signal : ::Signal, handler : ExplicitHandler) : Bool
    @@explicit_alias[signal] = handler
    !@@explicit_alias[signal]?.nil?
  end
end

handler = ->(signal : ::Signal) { nil }
puts Crystal::System::Signal.store_handler(::Signal::USR1, handler)
puts Crystal::System::Signal.store_direct(::Signal::USR2, handler)
puts Crystal::System::Signal.store_explicit_alias(::Signal::TERM, handler)
CRYSTAL

cat >"$WORK_DIR/expected.stdout" <<'EXPECTED'
true
true
true
EXPECTED

compile_and_run() {
  local label="$1" compiler="$2" original="$3"
  local output="$WORK_DIR/$label.bin"
  local status=0
  mkdir -p "$WORK_DIR/$label-cache"

  if [[ "$original" == 1 ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/$label-cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.build.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$WORK_DIR/probe.cr" \
      -o "$output" --link-flags=-fuse-ld=/usr/bin/ld \
      >"$WORK_DIR/$label.build.log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/$label-cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.build.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$WORK_DIR/probe.cr" \
      --no-ast-cache --no-llvm-cache -o "$output" \
      >"$WORK_DIR/$label.build.log" 2>&1 || status=$?
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$label]: compile failed ($status)" >&2
    tail -30 "$WORK_DIR/$label.build.log" >&2
    return 1
  fi

  status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.run.resources" \
    "$SAFE_RUNNER" "$output" 30 512 >"$WORK_DIR/$label.stdout" 2>"$WORK_DIR/$label.run.log" || status=$?
  if [[ "$status" -ne 0 ]] || ! grep -Fq '[EXIT: 0]' "$WORK_DIR/$label.run.log"; then
    echo "FAIL[$label]: runtime failed ($status)" >&2
    cat "$WORK_DIR/$label.run.log" >&2
    return 1
  fi
  if ! cmp -s "$WORK_DIR/expected.stdout" "$WORK_DIR/$label.stdout"; then
    echo "FAIL[$label]: output mismatch" >&2
    diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/$label.stdout" >&2 || true
    return 1
  fi
}

compile_and_run original "$ORIGINAL_CRYSTAL_BIN" 1
compile_and_run candidate "$COMPILER" 0

printf 'fixture_sha256=%s\n' "$(shasum -a 256 "$WORK_DIR/probe.cr" | awk '{print $1}')"
printf 'candidate_sha256=%s\n' "$(shasum -a 256 "$COMPILER" | awk '{print $1}')"
printf 'original_and_candidate_output=three true lines\n'
