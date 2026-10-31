#!/usr/bin/env bash
# Ancestor block queries must preserve the selected no-block dispatch bodies.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="${SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/exact-replay-callshape.XXXXXX")"
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
ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
cat >"$WORK/main.cr" <<'CRYSTAL'
lib ReplayOwnerOutput
  fun putchar(value : Int32) : Int32
end
class ReplayScheduler
  def find_next_runnable : Int32
    65
  end
  def find_next_runnable(&) : Int32
    yield
    67
  end
end
class ParallelReplayScheduler < ReplayScheduler
  def find_next_runnable : Int32
    66
  end
end
class SerialReplayScheduler < ReplayScheduler
end
def exercise_replay_owner(parallel : Bool)
  scheduler = parallel ? ParallelReplayScheduler.new : SerialReplayScheduler.new
  ReplayOwnerOutput.putchar(scheduler.find_next_runnable)
  scheduler.find_next_runnable { ReplayOwnerOutput.putchar(67) }
  ReplayOwnerOutput.putchar(scheduler.find_next_runnable)
end
exercise_replay_owner(false)
exercise_replay_owner(true)
ReplayOwnerOutput.putchar(10)
CRYSTAL
printf 'ACABCB\n' >"$WORK/expected"
for mode in original lazy eager; do
  mode_env=(env -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == original ]]; then
    args=("$ORIGINAL" 120 8192 build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}")
  else
    args=("$COMPILER" 120 8192 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
    [[ "$mode" != eager ]] || mode_env+=(ADAMAS_EAGER_MONO=1)
  fi
  if ! CRYSTAL_CACHE_DIR="$WORK/cache.$mode" "${mode_env[@]}" "$SAFE_RUNNER" \
      "${args[@]}" "$WORK/main.cr" -o "$WORK/$mode.bin" >"$WORK/$mode.compile.log" 2>&1; then
    cat "$WORK/$mode.compile.log" >&2
    exit 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK/$mode.bin" 5 512 \
      >"$WORK/$mode.stdout" 2>"$WORK/$mode.run.log"; then
    cat "$WORK/$mode.run.log" >&2
    exit 1
  fi
  diff -u "$WORK/expected" "$WORK/$mode.stdout"
  echo "PASS[$mode]: block queries preserve both concrete no-block scheduler branches"
done
