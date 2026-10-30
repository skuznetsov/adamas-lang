#!/usr/bin/env bash
# A satisfied virtual demand must survive later owner-layout invalidation.
# The unmodified prelude exercises this through ExecutionContext#stack_pool
# while starting its default Parallel scheduler, before user code runs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$COMPILER" && -n "$ORIGINAL" && -x "$ORIGINAL" ]] || exit 2

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/prelude-virtual-layout.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR/cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/hello.cr" <<'CRYSTAL'
puts "source-call hello"
CRYSTAL
printf 'source-call hello\n' >"$WORK_DIR/hello.expected"

cat >"$WORK_DIR/context.cr" <<'CRYSTAL'
def stable_pool(context : Fiber::ExecutionContext)
  context.stack_pool.same?(context.stack_pool)
end

puts stable_pool(Fiber::ExecutionContext.default)
CRYSTAL
printf 'true\n' >"$WORK_DIR/context.expected"

for name in hello context; do
  for stage in original candidate; do
    if [[ "$stage" == original ]]; then
      env CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$SAFE_RUNNER" "$ORIGINAL" 120 4096 \
        build "$WORK_DIR/$name.cr" -o "$WORK_DIR/$stage.$name" \
        >"$WORK_DIR/$stage.$name.compile.log" 2>&1 || {
        cat "$WORK_DIR/$stage.$name.compile.log" >&2
        exit 1
      }
    else
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/$name.cr" \
        -o "$WORK_DIR/$stage.$name" >"$WORK_DIR/$stage.$name.compile.log" 2>&1 || {
        cat "$WORK_DIR/$stage.$name.compile.log" >&2
        exit 1
      }
    fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/$stage.$name" 10 512 \
      >"$WORK_DIR/$stage.$name.stdout" 2>"$WORK_DIR/$stage.$name.run.log" || {
      cat "$WORK_DIR/$stage.$name.run.log" >&2
      exit 1
    }
    diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$stage.$name.stdout"
    echo "PASS[$stage/$name]: prelude startup and virtual getter"
  done
  diff -u "$WORK_DIR/original.$name.stdout" "$WORK_DIR/candidate.$name.stdout"
done
