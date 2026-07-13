#!/usr/bin/env bash
# Compile and run compiler specs file-by-file. A single aggregate spec binary
# is not viable because several suites define the same top-level helper aliases.
#
# Usage: scripts/run_all_specs.sh [jobs] [timeout_sec] [max_mem_mb] [paths...]
# Examples:
#   scripts/run_all_specs.sh
#   scripts/run_all_specs.sh 1 300 8192 spec/semantic
#   scripts/run_all_specs.sh 2 300 8192 spec/hir/hir_spec.cr spec/mir
#
# Successful runs delete their temporary logs. Failed runs retain them for
# diagnosis; set ADAMAS_KEEP_SPEC_LOGS=1 to retain logs from successful runs.

JOBS="${1:-1}"
TIMEOUT="${2:-300}"
MAX_MEM_MB="${3:-8192}"
# The produced-stage gate can spend up to 600s building stage2, 60s on its
# no-prelude HIR falsifier, 120s compiling its smoke, and 20s executing it. Its
# outer supervisor needs a separate budget so the default 300s per-file cap
# cannot kill a valid nested safe run.
PRODUCED_STAGE_TIMEOUT="${ADAMAS_PRODUCED_STAGE_SPEC_TIMEOUT:-900}"
shift $(( $# >= 3 ? 3 : $# ))

for value_name in JOBS TIMEOUT MAX_MEM_MB PRODUCED_STAGE_TIMEOUT; do
  eval "value=\${$value_name}"
  case "$value" in
    ''|*[!0-9]*|0)
      echo "$value_name must be a positive integer (got: $value)" >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
CRYSTAL_BIN="${CRYSTAL_BIN:-crystal}"
# Crystal 1.20 defaults each compiler process to four internal scheduler
# workers. Keep runner-owned compiler invocations single-worker by default;
# external JOBS remains the explicit process-level parallelism control.
CRYSTAL_WORKERS="${CRYSTAL_WORKERS:-1}"
export CRYSTAL_WORKERS
LOCK_KEY="$(printf '%s' "$ROOT_DIR" | cksum | awk '{print $1}')"
SPEC_LOCK_DIR="${ADAMAS_SPEC_RUN_LOCK_DIR:-${TMPDIR:-/tmp}/adamas-run-all-specs-$LOCK_KEY.lock}"
SPEC_LOCK_OWNED=0
OUTDIR=""
RESULTS=""
MANIFEST=""
KEEP_OUTPUT=0
GENERATED_COMPILER=""

release_spec_lock() {
  if [ "$SPEC_LOCK_OWNED" = "1" ] && [ -d "$SPEC_LOCK_DIR" ]; then
    owner_pid="$(sed -n '1p' "$SPEC_LOCK_DIR/pid" 2>/dev/null || true)"
    if [ "$owner_pid" = "$$" ]; then
      rm -f "$SPEC_LOCK_DIR/pid"
      rmdir "$SPEC_LOCK_DIR" 2>/dev/null || true
    fi
  fi
}

cleanup() {
  if [ -n "$GENERATED_COMPILER" ]; then
    rm -f "$GENERATED_COMPILER" "$GENERATED_COMPILER.dwarf"
  fi
  if [ -n "$OUTDIR" ]; then
    if [ "${ADAMAS_KEEP_SPEC_LOGS:-0}" = "1" ] || [ "$KEEP_OUTPUT" = "1" ]; then
      echo "Spec logs: $OUTDIR"
    else
      rm -rf "$OUTDIR"
    fi
  fi
  release_spec_lock
}
trap cleanup EXIT

acquire_spec_lock() {
  attempts=0
  while [ "$attempts" -lt 3 ]; do
    if mkdir "$SPEC_LOCK_DIR" 2>/dev/null; then
      if ! printf '%s\n' "$$" >"$SPEC_LOCK_DIR/pid"; then
        rmdir "$SPEC_LOCK_DIR" 2>/dev/null || true
        echo "Cannot write run_all_specs.sh lock owner: $SPEC_LOCK_DIR/pid" >&2
        return 3
      fi
      SPEC_LOCK_OWNED=1
      return 0
    fi

    owner_pid="$(sed -n '1p' "$SPEC_LOCK_DIR/pid" 2>/dev/null || true)"
    case "$owner_pid" in
      ''|*[!0-9]*|0)
        echo "run_all_specs.sh lock exists without a valid owner; refusing unsafe reclaim: $SPEC_LOCK_DIR" >&2
        return 3
        ;;
    esac

    if kill -0 "$owner_pid" 2>/dev/null; then
      echo "run_all_specs.sh is already running for this repository (pid=$owner_pid, lock=$SPEC_LOCK_DIR)" >&2
      echo "Concurrent Crystal spec invocations can deadlock; refusing to wait." >&2
      return 3
    fi

    # Serialize stale-owner reclamation so two contenders cannot steal a newly
    # acquired lock from one another between the liveness check and rename.
    if mkdir "$SPEC_LOCK_DIR/.reclaim" 2>/dev/null; then
      owner_pid_after_claim="$(sed -n '1p' "$SPEC_LOCK_DIR/pid" 2>/dev/null || true)"
      if [ "$owner_pid_after_claim" != "$owner_pid" ] || kill -0 "$owner_pid_after_claim" 2>/dev/null; then
        rmdir "$SPEC_LOCK_DIR/.reclaim" 2>/dev/null || true
        attempts=$((attempts + 1))
        continue
      fi

      stale_dir="$SPEC_LOCK_DIR.stale.$$"
      if mv "$SPEC_LOCK_DIR" "$stale_dir" 2>/dev/null; then
        echo "Reclaiming stale run_all_specs.sh lock (pid=$owner_pid, lock=$SPEC_LOCK_DIR)" >&2
        rm -rf "$stale_dir"
      else
        rmdir "$SPEC_LOCK_DIR/.reclaim" 2>/dev/null || true
      fi
    fi
    attempts=$((attempts + 1))
  done

  echo "Could not acquire run_all_specs.sh lock after stale-owner recovery: $SPEC_LOCK_DIR" >&2
  return 3
}

acquire_spec_lock || exit $?

OUTDIR="$(mktemp -d /tmp/adamas_spec_run.XXXXXX)"
RESULTS="$OUTDIR/results.txt"
MANIFEST="$OUTDIR/specs.list0"

if [ "$#" -eq 0 ]; then
  set -- spec
fi

cd "$ROOT_DIR" || exit 1
for path in "$@"; do
  if [ ! -e "$path" ]; then
    echo "Spec path does not exist: $path" >&2
    KEEP_OUTPUT=1
    exit 2
  fi
done
find "$@" -type f -name '*_spec.cr' -print0 | sort -z >"$MANIFEST"
# Keep the manifest NUL-safe while moving only the two known expensive specs to
# the tail. The source is already sorted, so appending each class as we scan
# preserves sorted order within ordinary and deferred classes. With JOBS>1 this
# remains scheduling order (workers can overlap classes), not a global barrier.
ORDINARY_MANIFEST="$OUTDIR/ordinary-specs.list0"
EXPENSIVE_MANIFEST="$OUTDIR/expensive-specs.list0"
: >"$ORDINARY_MANIFEST"
: >"$EXPENSIVE_MANIFEST"
while IFS= read -r -d '' file; do
  case "${file##*/}" in
    produced_stage_bootstrap_spec.cr|generated_runtime_integration_spec.cr)
      printf '%s\0' "$file" >>"$EXPENSIVE_MANIFEST"
      ;;
    *)
      printf '%s\0' "$file" >>"$ORDINARY_MANIFEST"
      ;;
  esac
done <"$MANIFEST"
cat "$ORDINARY_MANIFEST" "$EXPENSIVE_MANIFEST" >"$MANIFEST"
TOTAL="$(tr -cd '\0' <"$MANIFEST" | wc -c | tr -d ' ')"

echo "Spec files: $TOTAL  (jobs=$JOBS timeout=${TIMEOUT}s max_mem=${MAX_MEM_MB}MB)"
if [ "$TOTAL" -eq 0 ]; then
  echo "No *_spec.cr files found under: $*" >&2
  KEEP_OUTPUT=1
  exit 2
fi

if tr '\0' '\n' <"$MANIFEST" | grep -Eq '/(generated_runtime_integration|produced_stage_bootstrap)_spec\.cr$'; then
  if [ -z "${ADAMAS_SPEC_COMPILER:-}" ]; then
    GENERATED_COMPILER="$OUTDIR/adamas-spec-compiler"
    echo "Building fresh generated-spec compiler..."
    if ! "$RUN_SAFE" "$CRYSTAL_BIN" "$TIMEOUT" "$MAX_MEM_MB" \
      build src/adamas.cr -o "$GENERATED_COMPILER" --error-trace \
      >"$OUTDIR/generated-compiler-build.log" 2>&1; then
      echo "Fresh generated-spec compiler build failed" >&2
      KEEP_OUTPUT=1
      exit 1
    fi
    ADAMAS_SPEC_COMPILER="$GENERATED_COMPILER"
  fi
  if [ ! -x "$ADAMAS_SPEC_COMPILER" ]; then
    echo "ADAMAS_SPEC_COMPILER is not executable: $ADAMAS_SPEC_COMPILER" >&2
    KEEP_OUTPUT=1
    exit 2
  fi
  export ADAMAS_SPEC_COMPILER
fi

run_one() {
  local file="$1"
  local safe="${file//\//_}"
  local log="$OUTDIR/$safe.log"
  local rc
  local run_timeout="$TIMEOUT"
  local summary
  local failures
  local diagnostic

  case "$file" in
    */produced_stage_bootstrap_spec.cr)
      run_timeout="$PRODUCED_STAGE_TIMEOUT"
      ;;
  esac

  if "$RUN_SAFE" "$CRYSTAL_BIN" "$run_timeout" "$MAX_MEM_MB" \
    spec "$file" --no-color >"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi

  summary="$(grep -E 'examples?,.*failures?' "$log" | tail -1)"
  if [ -z "$summary" ]; then
    diagnostic="$(grep -m1 -E 'Error:|\[KILL\]|\[CRASH\]' "$log" | tr '\n' ' ')"
    if grep -q '\[KILL\] Timeout' "$log"; then
      echo "TIMEOUT|$file|${diagnostic:-rc=$rc}"
    else
      echo "COMPILE_FAIL|$file|rc=$rc ${diagnostic}"
    fi
    return
  fi

  failures="$(echo "$summary" | grep -oE '[0-9]+ failures?' | grep -oE '[0-9]+' || true)"
  if [ "${failures:-0}" -eq 0 ] && [ "$rc" -eq 0 ]; then
    echo "PASS|$file|$summary"
  else
    echo "FAIL|$file|$summary"
  fi
}
# Crystal 1.20 names every `crystal spec` executable
# `${CRYSTAL_CACHE_DIR}/crystal-run-spec.tmp`. Parallel files must therefore
# never share a cache directory. Fixed workers own distinct caches and process
# their assigned files sequentially, retaining cache reuse inside each worker.
index=0
while IFS= read -r -d '' file; do
  worker=$((index % JOBS))
  printf '%s\0' "$file" >>"$OUTDIR/worker-$worker.list0"
  index=$((index + 1))
done <"$MANIFEST"

worker_pids=""
worker=0
while [ "$worker" -lt "$JOBS" ]; do
  part_manifest="$OUTDIR/worker-$worker.list0"
  part_results="$OUTDIR/worker-$worker.results"
  : >"$part_results"
  (
    export CRYSTAL_CACHE_DIR="$OUTDIR/cache-$worker"
    if [ -f "$part_manifest" ]; then
      while IFS= read -r -d '' file; do
        run_one "$file"
      done <"$part_manifest"
    fi
  ) >"$part_results" &
  worker_pids="$worker_pids $!"
  worker=$((worker + 1))
done

worker_rc=0
for worker_pid in $worker_pids; do
  if ! wait "$worker_pid"; then
    worker_rc=1
  fi
done

if [ ! -d "$OUTDIR" ]; then
  echo "Spec output directory disappeared during the run: $OUTDIR" >&2
  exit 1
fi

missing_worker_results=0
worker=0
while [ "$worker" -lt "$JOBS" ]; do
  part_results="$OUTDIR/worker-$worker.results"
  if [ ! -f "$part_results" ]; then
    echo "Spec worker result disappeared: $part_results" >&2
    missing_worker_results=1
  fi
  worker=$((worker + 1))
done
if [ "$missing_worker_results" -ne 0 ]; then
  KEEP_OUTPUT=1
  exit 1
fi

if ! : >"$RESULTS"; then
  echo "Cannot create aggregate spec results: $RESULTS" >&2
  KEEP_OUTPUT=1
  exit 1
fi
worker=0
while [ "$worker" -lt "$JOBS" ]; do
  if ! cat "$OUTDIR/worker-$worker.results" >>"$RESULTS"; then
    echo "Cannot aggregate spec worker result: $OUTDIR/worker-$worker.results" >&2
    KEEP_OUTPUT=1
    exit 1
  fi
  worker=$((worker + 1))
done

classified="$(wc -l <"$RESULTS" | tr -d ' ')"
harness_fail=0
if [ "$worker_rc" -ne 0 ]; then
  echo "Spec worker orchestration failed" >&2
  harness_fail=1
fi
if [ "$classified" -ne "$TOTAL" ]; then
  echo "Spec result count mismatch: classified=$classified expected=$TOTAL" >&2
  harness_fail=1
fi

echo ""
echo "======================================== SPEC SUMMARY ========================================"
sort "$RESULTS" >"$OUTDIR/results_sorted.txt"
pass="$(grep -c '^PASS|' "$RESULTS" || true)"
fail="$(grep -c '^FAIL|' "$RESULTS" || true)"
compile_fail="$(grep -c '^COMPILE_FAIL|' "$RESULTS" || true)"
timeout_count="$(grep -c '^TIMEOUT|' "$RESULTS" || true)"
recognized=$((pass + fail + compile_fail + timeout_count))
if [ "$recognized" -ne "$TOTAL" ]; then
  echo "Spec classification mismatch: recognized=$recognized expected=$TOTAL" >&2
  harness_fail=1
fi
echo "Files: $TOTAL  |  PASS=$pass  FAIL=$fail  COMPILE_FAIL=$compile_fail  TIMEOUT=$timeout_count"
echo ""
echo "--- Non-passing files ---"
grep -vE '^PASS\|' "$OUTDIR/results_sorted.txt" || echo "(none)"
echo ""
echo "--- Aggregate examples/failures ---"
awk -F'|' '
  {
    if (match($3, /[0-9]+ examples?/)) {
      value = substr($3, RSTART, RLENGTH)
      sub(/ .*/, "", value)
      examples += value
    }
    if (match($3, /[0-9]+ failures?/)) {
      value = substr($3, RSTART, RLENGTH)
      sub(/ .*/, "", value)
      failures += value
    }
  }
  END {
    print "total examples: " examples + 0
    print "total failures: " failures + 0
  }
' "$RESULTS"

if [ "$harness_fail" -ne 0 ] || [ "$fail" -ne 0 ] || [ "$compile_fail" -ne 0 ] || [ "$timeout_count" -ne 0 ]; then
  KEEP_OUTPUT=1
  exit 1
fi

exit 0
