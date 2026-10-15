#!/usr/bin/env bash
# Forwarded and returned blocks retain each invocation's captured environment.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL" && -x "$SAFE_RUNNER" ]] || exit 2
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forwarded-block-capture.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
class Deferred
  @callback : Proc(Int32)

  def initialize(&@callback : -> Int32)
  end

  def call
    @callback.call
  end
end

def deferred(&callback : -> Int32)
  Deferred.new(&callback)
end

def make_deferred(value : Int32)
  deferred { value }
end

first = make_deferred(101)
second = make_deferred(202)
puts first.call
puts second.call

def retained(&callback : -> Int32)
  callback
end

def make_retained(value : Int32)
  retained { value + 1 }
end

third = make_retained(303)
fourth = make_retained(404)
puts third.call
puts fourth.call
CRYSTAL
printf '101\n202\n304\n405\n' >"$WORK_DIR/expected"

for stage in original candidate; do
  compiler="$COMPILER"
  args=("$WORK_DIR/probe.cr" --no-prelude --no-ast-cache --no-llvm-cache -o "$WORK_DIR/$stage")
  if [[ "$stage" == original ]]; then
    compiler="$ORIGINAL_CRYSTAL"
    args=(build "$WORK_DIR/probe.cr" -o "$WORK_DIR/$stage" --link-flags=-fuse-ld=/usr/bin/ld)
  fi
  if ! env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/$stage.cache" \
      ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.build.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "${args[@]}" \
      >"$WORK_DIR/$stage.build.log" 2>&1; then
    tail -35 "$WORK_DIR/$stage.build.log" >&2
    exit 1
  fi
  rm -rf "$WORK_DIR/$stage.cache"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.run.resources" \
      "$SAFE_RUNNER" "$WORK_DIR/$stage" 15 1024 \
      >"$WORK_DIR/$stage.stdout" 2>"$WORK_DIR/$stage.run.log"; then
    tail -35 "$WORK_DIR/$stage.run.log" >&2
    exit 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$stage.run.log"
  diff -u "$WORK_DIR/expected" "$WORK_DIR/$stage.stdout"
done
printf 'PASS: forwarded and returned callbacks retain independent environments\n'
