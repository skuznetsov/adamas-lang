#!/usr/bin/env bash
# Bootstrap ladder: stage1 = host Crystal builds adamas; stage2+ = previous
# binary builds adamas again (plain flags only — no --stats in the ladder).
#
# Usage (from repo root):
#   scripts/bootstrap_chain.sh [--stages N] [--host PATH] [--source PATH] [--out DIR]
#       [--timeout SEC] [--mem MB]
#
# Environment (defaults if flags omitted):
#   CRYSTAL_HOST   — host compiler for stage1 (default: crystal)
#   BOOTSTRAP_CHAIN_STAGES / BOOTSTRAP_CHAIN_SOURCE / BOOTSTRAP_CHAIN_OUT
#   BOOTSTRAP_TIMEOUT_SEC — run_safe timeout for stage2+ (default 900)
#   BOOTSTRAP_MEM_MB      — run_safe RSS cap for stage2+ (default 12288)
#   BOOTSTRAP_SMOKE_PLAIN_MEM_MB — RSS cap for plain smoke only (default 8192).
#       Plain smoke uses the full prelude; 1024MB triggers false OOM under run_safe.
#
# Stage1 uses:  host build SOURCE -o OUT/cv2_s1 --error-trace
# Stage2+:      scripts/run_safe.sh PREV timeout mem SOURCE -o OUT/cv2_sN
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

STAGES="${BOOTSTRAP_CHAIN_STAGES:-5}"
HOST_CRYSTAL="${CRYSTAL_HOST:-crystal}"
SOURCE_REL="${BOOTSTRAP_CHAIN_SOURCE:-src/adamas.cr}"
OUT_DIR="${BOOTSTRAP_CHAIN_OUT:-}"
OUT_DIR_EXPLICIT=0
if [[ -n "${BOOTSTRAP_CHAIN_OUT:-}" ]]; then
  OUT_DIR_EXPLICIT=1
fi
TIMEOUT_SEC="${BOOTSTRAP_TIMEOUT_SEC:-900}"
MEM_MB="${BOOTSTRAP_MEM_MB:-12288}"
SMOKE_PLAIN_MEM_MB="${BOOTSTRAP_SMOKE_PLAIN_MEM_MB:-8192}"
ALLOW_DIRTY="${BOOTSTRAP_ALLOW_DIRTY:-0}"
CACHE_MODE_RAW="${BOOTSTRAP_CACHE_MODE:-${ADAMAS_CACHE_MODE:-${CRYSTAL_CACHE_DIR:-}}}"

usage() {
  cat <<'USAGE'
Bootstrap ladder (stage1 = host Crystal builds adamas; stage2+ = previous
binary builds adamas again). Plain self-host only — no --stats on the ladder.

Usage:
  scripts/bootstrap_chain.sh [--stages N] [--host PATH] [--source PATH] [--out DIR]
      [--timeout SEC] [--mem MB]

Environment (optional):
  CRYSTAL_HOST          Host compiler for stage1 (default: crystal)
  BOOTSTRAP_CHAIN_STAGES / BOOTSTRAP_CHAIN_SOURCE / BOOTSTRAP_CHAIN_OUT
  BOOTSTRAP_TIMEOUT_SEC run_safe timeout for stage2+ (default: 900)
  BOOTSTRAP_MEM_MB      run_safe RSS cap for stage2+ (default: 12288)
  BOOTSTRAP_SMOKE_PLAIN_MEM_MB  RSS cap for plain smoke only (default: 8192)

Stage1:  host build SOURCE -o OUT/cv2_s1 --error-trace
Stage2+: scripts/run_safe.sh PREV timeout mem SOURCE -o OUT/cv2_sN
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stages)
      STAGES="$2"
      shift 2
      ;;
    --host)
      HOST_CRYSTAL="$2"
      shift 2
      ;;
    --source)
      SOURCE_REL="$2"
      shift 2
      ;;
    --out)
      OUT_DIR="$2"
      OUT_DIR_EXPLICIT=1
      shift 2
      ;;
    --timeout)
      TIMEOUT_SEC="$2"
      shift 2
      ;;
    --mem)
      MEM_MB="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ "$1" == -* ]]; then
        echo "error: unknown option: $1" >&2
        exit 1
      fi
      HOST_CRYSTAL="$1"
      shift
      ;;
  esac
done

if ! [[ "$STAGES" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --stages must be a positive integer" >&2
  exit 1
fi

if ! [[ "$TIMEOUT_SEC" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --timeout must be a positive integer" >&2
  exit 1
fi

if ! [[ "$MEM_MB" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --mem must be a positive integer" >&2
  exit 1
fi

if ! [[ "$ALLOW_DIRTY" == "0" || "$ALLOW_DIRTY" == "1" ]]; then
  echo "error: BOOTSTRAP_ALLOW_DIRTY must be 0 or 1" >&2
  exit 1
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="/tmp/adamas_bootstrap_chain_${USER:-user}_$$"
fi
if [[ -L "$OUT_DIR" ]]; then
  echo "error: output directory must not be a symlink: $OUT_DIR" >&2
  exit 1
fi
mkdir -p "$OUT_DIR" || {
  echo "error: unable to create output directory: $OUT_DIR" >&2
  exit 1
}

# An output directory is a safety boundary.  Reusing it would make an
# exit-zero compiler that emitted no artifact indistinguishable from a
# successful rebuild of an older artifact.  Requiring an empty directory is
# deliberately conservative; callers can choose a fresh run directory.
if [[ -d "$OUT_DIR/.bootstrap-chain.lock" ]]; then
  echo "error: output directory is already locked by another bootstrap run: $OUT_DIR" >&2
  exit 1
fi
if ! OUT_ENTRY="$(find "$OUT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)"; then
  echo "error: unable to inspect output directory for stale entries: $OUT_DIR" >&2
  exit 1
fi
if [[ -n "$OUT_ENTRY" ]]; then
  echo "error: output directory must be empty for a fresh bootstrap run: $OUT_DIR" >&2
  exit 1
fi

LOCK_DIR="$OUT_DIR/.bootstrap-chain.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "error: output directory is already locked by another bootstrap run: $OUT_DIR" >&2
  exit 1
fi

RUN_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
printf '%s\n' "$RUN_ID" >"$LOCK_DIR/run_id"

cleanup_bootstrap_lock() {
  rm -f "$LOCK_DIR/run_id" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup_bootstrap_lock EXIT

SOURCE_ABS="$REPO_ROOT/$SOURCE_REL"
NO_PRELUDE_ORACLE="$REPO_ROOT/regression_tests/combined/test_no_prelude_interpolation.cr"
SMOKE_SRC="$OUT_DIR/_smoke_puts42.cr"

if [[ "$SOURCE_REL" == /* ]]; then
  echo "error: --source must be a repository-relative path" >&2
  exit 1
fi
if [[ ! -f "$SOURCE_ABS" ]]; then
  echo "error: source not found: $SOURCE_ABS" >&2
  exit 1
fi

ROOT_REAL="$(cd "$REPO_ROOT" && pwd -P)"
SOURCE_DIR_REAL="$(cd "$(dirname "$SOURCE_ABS")" 2>/dev/null && pwd -P || true)"
SOURCE_BASE="$(basename "$SOURCE_ABS")"
SOURCE_CANONICAL="${SOURCE_DIR_REAL:+$SOURCE_DIR_REAL/$SOURCE_BASE}"
case "$SOURCE_CANONICAL" in
  "$ROOT_REAL"/*) ;;
  *)
    echo "error: --source resolves outside the repository" >&2
    exit 1
    ;;
esac
if [[ -L "$SOURCE_ABS" ]]; then
  echo "error: --source must not be a symlink" >&2
  exit 1
fi
SOURCE_ABS="$SOURCE_CANONICAL"
SOURCE_SCOPE_REL="${SOURCE_DIR_REAL#"$ROOT_REAL"/}"
if [[ "$SOURCE_SCOPE_REL" == "$SOURCE_DIR_REAL" ]]; then
  SOURCE_SCOPE_REL="."
fi
if [[ "$SOURCE_SCOPE_REL" == "." ]]; then
  echo "error: --source must live in a repository subdirectory so its evidence scope excludes repository metadata" >&2
  exit 1
fi
OUT_REAL="$(cd "$OUT_DIR" && pwd -P)"
SOURCE_SCOPE_REAL="$ROOT_REAL/$SOURCE_SCOPE_REL"
case "$OUT_REAL" in
  "$SOURCE_SCOPE_REAL"|"$SOURCE_SCOPE_REAL"/*)
    echo "error: output directory must be outside the bootstrap source scope: $SOURCE_SCOPE_REAL" >&2
    exit 1
    ;;
esac
if [[ ! -f "$NO_PRELUDE_ORACLE" ]]; then
  echo "error: no-prelude oracle not found: $NO_PRELUDE_ORACLE" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  HASH_BACKEND="shasum"
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_BACKEND="sha256sum"
else
  echo "error: a SHA-256 utility (shasum or sha256sum) is required" >&2
  exit 1
fi

sha256_stream() {
  if [[ "$HASH_BACKEND" == "shasum" ]]; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

sha256_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 1
  fi
  if [[ "$HASH_BACKEND" == "shasum" ]]; then
    shasum -a 256 -- "$path" | awk '{print $1}'
  else
    sha256sum -- "$path" | awk '{print $1}'
  fi
}

sha256_text() {
  printf '%s' "$1" | sha256_stream
}

hash_source_tree() {
  local scope="${1:-$SOURCE_SCOPE_REL}"
  (
    cd "$REPO_ROOT" || exit 1
    if [[ "$HASH_BACKEND" == "shasum" ]]; then
      find "$scope" -type f -exec shasum -a 256 {} + 2>/dev/null |
        LC_ALL=C sort | shasum -a 256 | awk '{print $1}'
    else
      find "$scope" -type f -exec sha256sum {} + 2>/dev/null |
        LC_ALL=C sort | sha256sum | awk '{print $1}'
    fi
  ) | sha256_stream
}

safe_manifest_value() {
  # Preserve readable printable values while replacing all control characters,
  # including newlines, so untrusted paths/flags cannot inject manifest rows.
  printf '%s' "$1" | LC_ALL=C tr -c '[:print:]' '_'
}

base64_manifest_value() {
  printf '%s' "$1" | base64 | tr -d '\r\n'
}

resolve_tool_path() {
  local tool="$1"
  if [[ "$tool" == */* ]]; then
    printf '%s' "$tool"
  else
    command -v "$tool" 2>/dev/null || printf '%s' "$tool"
  fi
}

source_git_status=""
source_git_diff=""
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_AVAILABLE=1
  GIT_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  source_git_status="$(git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all -- "$SOURCE_SCOPE_REL" 2>/dev/null || true)"
  source_git_diff="$(git -C "$REPO_ROOT" diff --no-ext-diff --binary -- "$SOURCE_SCOPE_REL" 2>/dev/null || true)"
else
  echo "error: git provenance is unavailable for bootstrap source evidence" >&2
  exit 1
fi

if [[ "$GIT_AVAILABLE" == "1" ]]; then
  if [[ -n "$source_git_status" ]]; then
    SOURCE_GIT_STATE="dirty"
  else
    SOURCE_GIT_STATE="clean"
  fi
else
  SOURCE_GIT_STATE="unknown"
fi

if [[ "$SOURCE_GIT_STATE" == "dirty" && "$ALLOW_DIRTY" != "1" ]]; then
  echo "error: source tree is dirty; set BOOTSTRAP_ALLOW_DIRTY=1 to record an explicitly dirty run" >&2
  exit 1
fi

SOURCE_GIT_STATUS_SHA256="$(sha256_text "$source_git_status")"
SOURCE_GIT_DIFF_SHA256="$(sha256_text "$source_git_diff")"
SOURCE_CONTENT_SHA256="$(sha256_file "$SOURCE_ABS" || true)"
SOURCE_TREE_SHA256="$(hash_source_tree || true)"
if [[ -z "$SOURCE_CONTENT_SHA256" || -z "$SOURCE_TREE_SHA256" ]]; then
  echo "error: unable to hash the bootstrap source tree" >&2
  exit 1
fi

HOST_COMPILER_RESOLVED="$(resolve_tool_path "$HOST_CRYSTAL")"
HOST_COMPILER_SHA256="$(sha256_file "$HOST_COMPILER_RESOLVED" || true)"
if [[ -z "$HOST_COMPILER_SHA256" ]]; then
  echo "error: host compiler is not a regular file that can be hashed: $HOST_CRYSTAL" >&2
  exit 1
fi

BOOTSTRAP_CHAIN_SCRIPT_SHA256="$(sha256_file "$SCRIPT_DIR/bootstrap_chain.sh" || true)"
RUN_SAFE_SCRIPT_SHA256="$(sha256_file "$SCRIPT_DIR/run_safe.sh" || true)"
PATH_SHA256="$(sha256_text "${PATH-}")"
if [[ -z "$BOOTSTRAP_CHAIN_SCRIPT_SHA256" || -z "$RUN_SAFE_SCRIPT_SHA256" ]]; then
  echo "error: unable to hash bootstrap harness scripts" >&2
  exit 1
fi

HOST_TOOLCHAIN_ID="$(uname -s 2>/dev/null || printf 'unknown')/$(uname -m 2>/dev/null || printf 'unknown')/$(uname -r 2>/dev/null || printf 'unknown')"

# Record only names and a digest of values for bootstrap-affecting variables;
# raw environment contents (which may contain credentials or private paths) are
# intentionally excluded from the manifest.
BOOTSTRAP_ENV_NAME_LIST=(
  BOOTSTRAP_CHAIN_STAGES BOOTSTRAP_CHAIN_SOURCE BOOTSTRAP_CHAIN_OUT
  BOOTSTRAP_TIMEOUT_SEC BOOTSTRAP_MEM_MB BOOTSTRAP_SMOKE_PLAIN_MEM_MB
  CRYSTAL_HOST BOOTSTRAP_CACHE_MODE ADAMAS_CACHE_MODE BOOTSTRAP_ALLOW_DIRTY
  CRYSTAL_CACHE_DIR
)

CONTAMINATING_ENV_NAMES=""
for env_name in $(env | sed -n 's/=.*//p'); do
  case "$env_name" in
    ADAMAS_STOP_AFTER_*|RUN_SAFE_PASSTHROUGH_STDIO)
      CONTAMINATING_ENV_NAMES+="${env_name} "
      ;;
    ADAMAS_*|CRYSTAL_*|RUN_SAFE_*)
      already_listed=0
      for listed_name in "${BOOTSTRAP_ENV_NAME_LIST[@]}"; do
        if [[ "$listed_name" == "$env_name" ]]; then
          already_listed=1
          break
        fi
      done
      if [[ "$already_listed" == "0" ]]; then
        BOOTSTRAP_ENV_NAME_LIST+=("$env_name")
      fi
      ;;
  esac
done

if [[ -n "$CONTAMINATING_ENV_NAMES" ]]; then
  echo "error: bootstrap control environment is unsafe: ${CONTAMINATING_ENV_NAMES% }" >&2
  exit 1
fi

BOOTSTRAP_ENV_NAMES="$(IFS=,; printf '%s' "${BOOTSTRAP_ENV_NAME_LIST[*]}")"
BOOTSTRAP_ENV_HASH_INPUT=""
for env_name in "${BOOTSTRAP_ENV_NAME_LIST[@]}"; do
  env_value="${!env_name-}"
  BOOTSTRAP_ENV_HASH_INPUT+="${env_name}=${env_value}"$'\n'
done
BOOTSTRAP_ENV_SHA256="$(sha256_text "$BOOTSTRAP_ENV_HASH_INPUT")"

if [[ -z "$CACHE_MODE_RAW" ]]; then
  CACHE_MODE="unknown"
else
  CACHE_MODE="declared"
fi
CACHE_MODE_VALUE_SHA256="$(sha256_text "$CACHE_MODE_RAW")"

cat > "$SMOKE_SRC" <<'EOF'
puts 42
EOF

parse_time_real() {
  local logfile="$1"
  # Portable time -p prints "real N.NN" and preserves the child exit status.
  # macOS time -l performs a kern.clockrate sysctl after the child exits; in a
  # sandbox that probe fails and changes an otherwise successful build to RC 1.
  awk '$1 == "real" && NF >= 2 { v = $2 } END { if (v != "") print v }' "$logfile"
}

parse_time_l_max_rss_bytes() {
  local logfile="$1"
  # Newer run_safe versions emit a truthful, portable resource summary.  Keep
  # the legacy maximum-resident-set parser as a fallback for host builds.
  awk '
    /^\[RESOURCE\]/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^max_rss_kb=/) {
          split($i, a, "=")
          if (a[2] ~ /^[0-9]+$/) {
            print a[2] * 1024
            found = 1
          }
        }
      }
    }
    /maximum resident set size/ && !found { r = $1 }
    END { if (!found && r != "") print r }
  ' "$logfile"
}

parse_resource_summary() {
  local logfile="$1"
  awk '/^\[RESOURCE\]/ { line = $0 } END { print line }' "$logfile"
}

bytes_to_mb() {
  local b="$1"
  if [[ -z "$b" || "$b" == "0" ]]; then
    echo ""
    return
  fi
  awk -v n="$b" 'BEGIN { printf "%.2f", n / 1048576.0 }'
}

# Returns: exit code of build in $1; sets WALL_REAL, PEAK_MB, LOG
run_stage1_host() {
  local out_bin="$1"
  local logfile="$2"
  (
    cd "$REPO_ROOT"
    /usr/bin/time -p "$SCRIPT_DIR/run_safe.sh" "$HOST_COMPILER_RESOLVED" "$TIMEOUT_SEC" "$MEM_MB" \
      build "$SOURCE_REL" -o "$out_bin" --error-trace
  ) >"$logfile" 2>&1
}

run_stageN_selfhost() {
  local compiler="$1"
  local out_bin="$2"
  local logfile="$3"
  (
    cd "$REPO_ROOT"
    /usr/bin/time -p "$SCRIPT_DIR/run_safe.sh" "$compiler" "$TIMEOUT_SEC" "$MEM_MB" \
      "$SOURCE_REL" -o "$out_bin"
  ) >"$logfile" 2>&1
}

run_compiled_smoke() {
  local binary="$1"
  local marker="$2"
  local runtime_log="$3"
  local marker_count
  local stdout_line_count

  if ! "$SCRIPT_DIR/run_safe.sh" "$binary" 10 512 >"$runtime_log" 2>&1; then
    cat "$runtime_log"
    return 1
  fi
  cat "$runtime_log"
  marker_count="$(awk -v wanted="$marker" '
    $0 == "=== STDOUT ===" { in_stdout = 1; next }
    $0 == "=== STDERR ===" { in_stdout = 0 }
    in_stdout && $0 == wanted { count += 1 }
    END { print count + 0 }
  ' "$runtime_log")"
  stdout_line_count="$(awk '
    $0 == "=== STDOUT ===" { in_stdout = 1; next }
    $0 == "=== STDERR ===" { in_stdout = 0 }
    in_stdout && length($0) > 0 { count += 1 }
    END { print count + 0 }
  ' "$runtime_log")"
  if [[ "$marker_count" != "1" || "$stdout_line_count" != "1" ]]; then
    echo "error: smoke runtime output mismatch: binary=$binary marker=$marker marker_count=$marker_count stdout_lines=$stdout_line_count" >&2
    return 1
  fi
}

run_smoke_plain() {
  local compiler="$1"
  local logfile="$2"
  local binary="$OUT_DIR/_smoke_puts42.bin"
  rm -f "$binary"
  (
    cd "$REPO_ROOT"
    /usr/bin/time -p "$SCRIPT_DIR/run_safe.sh" "$compiler" 60 "$SMOKE_PLAIN_MEM_MB" \
      "$SMOKE_SRC" -o "$binary" || exit $?
    if [[ ! -f "$binary" || -L "$binary" || ! -x "$binary" || ! -s "$binary" ]]; then
      echo "error: smoke compiler exited successfully but produced no fresh executable: $binary" >&2
      exit 1
    fi
    run_compiled_smoke "$binary" "42" "$OUT_DIR/_smoke_puts42.runtime.log"
  ) >"$logfile" 2>&1
}

run_smoke_noprelude() {
  local compiler="$1"
  local logfile="$2"
  local binary="$OUT_DIR/_smoke_noprel.bin"
  rm -f "$binary"
  (
    cd "$REPO_ROOT"
    /usr/bin/time -p "$SCRIPT_DIR/run_safe.sh" "$compiler" 120 1024 \
      "$NO_PRELUDE_ORACLE" --no-prelude -o "$binary" || exit $?
    if [[ ! -f "$binary" || -L "$binary" || ! -x "$binary" || ! -s "$binary" ]]; then
      echo "error: smoke compiler exited successfully but produced no fresh executable: $binary" >&2
      exit 1
    fi
    run_compiled_smoke "$binary" "noprelude_interp_ok" "$OUT_DIR/_smoke_noprel.runtime.log"
  ) >"$logfile" 2>&1
}

stderr_tail() {
  local logfile="$1"
  local n="${2:-80}"
  if [[ -f "$logfile" ]]; then
    echo "--- tail ($n lines): $logfile ---"
    tail -n "$n" "$logfile"
  fi
}

echo "=== Bootstrap chain ==="
echo "repo:       $REPO_ROOT"
echo "stages:     $STAGES"
echo "host (s1):  $HOST_CRYSTAL"
echo "source:     $SOURCE_REL"
echo "out dir:    $OUT_DIR"
echo "stage2+ run_safe: timeout=${TIMEOUT_SEC}s mem=${MEM_MB}MB"
echo "smoke plain run_safe: timeout=60s mem=${SMOKE_PLAIN_MEM_MB}MB (override BOOTSTRAP_SMOKE_PLAIN_MEM_MB)"
echo ""

declare -a ST_OK ST_BIN ST_WALL ST_PEAK ST_SMOKE_P ST_SMOKE_N ST_LOG
declare -a ST_PRODUCER ST_PRODUCER_HASH ST_PRODUCER_HASH_END ST_PRODUCER_MATCH ST_OUTPUT_HASH ST_OUTPUT_HASH_END ST_FLAGS ST_FLAGS_B64
declare -a ST_STARTED ST_FINISHED ST_RESOURCE ST_SMOKE_P_HASH ST_SMOKE_N_HASH ST_CACHE
FIRST_FAIL=""
FIRST_FAIL_KIND=""
FIRST_SYMPTOM=""

MANIFEST="$OUT_DIR/bootstrap_chain.manifest"

write_manifest() {
  local finished_at
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local tmp_manifest="$MANIFEST.tmp.$$"

  {
    echo "format_version=2"
    echo "manifest_schema=key_value;*_b64=base64;*_text=printable_control_escaped"
    echo "run_id=$(safe_manifest_value "$RUN_ID")"
    echo "run_started_at=$(safe_manifest_value "$RUN_STARTED_AT")"
    echo "run_finished_at=$(safe_manifest_value "$finished_at")"
    echo "repo_root=$(safe_manifest_value "$REPO_ROOT")"
    echo "repo_root_b64=$(base64_manifest_value "$REPO_ROOT")"
    echo "source=$(safe_manifest_value "$SOURCE_REL")"
    echo "source_b64=$(base64_manifest_value "$SOURCE_REL")"
    echo "source_scope=$(safe_manifest_value "$SOURCE_SCOPE_REL")"
    echo "source_content_sha256=$SOURCE_CONTENT_SHA256"
    echo "source_content_hash=$SOURCE_CONTENT_SHA256"
    echo "source_content_sha256_end=$(safe_manifest_value "${SOURCE_CONTENT_SHA256_END:-unknown}")"
    echo "source_tree_sha256=$SOURCE_TREE_SHA256"
    echo "source_tree_hash=$SOURCE_TREE_SHA256"
    echo "source_tree_sha256_end=$(safe_manifest_value "${SOURCE_TREE_SHA256_END:-unknown}")"
    echo "source_git_head=$(safe_manifest_value "$GIT_HEAD")"
    echo "source_git_state=$(safe_manifest_value "$SOURCE_GIT_STATE")"
    echo "source_git_status_sha256=$SOURCE_GIT_STATUS_SHA256"
    echo "source_git_diff_sha256=$SOURCE_GIT_DIFF_SHA256"
    echo "source_hash_consistent=$(safe_manifest_value "${SOURCE_HASH_CONSISTENT:-unknown}")"
    echo "host_compiler=$(safe_manifest_value "$HOST_CRYSTAL")"
    echo "host_compiler_b64=$(base64_manifest_value "$HOST_CRYSTAL")"
    echo "host_compiler_resolved=$(safe_manifest_value "$HOST_COMPILER_RESOLVED")"
    echo "host_compiler_resolved_b64=$(base64_manifest_value "$HOST_COMPILER_RESOLVED")"
    echo "host_compiler_sha256=$HOST_COMPILER_SHA256"
    echo "host_toolchain_identity=$(safe_manifest_value "$HOST_TOOLCHAIN_ID")"
    echo "host_toolchain=$(safe_manifest_value "$HOST_TOOLCHAIN_ID")"
    echo "harness_bootstrap_chain_sha256=$BOOTSTRAP_CHAIN_SCRIPT_SHA256"
    echo "harness_run_safe_sha256=$RUN_SAFE_SCRIPT_SHA256"
    echo "path_sha256=$PATH_SHA256"
    echo "bootstrap_env_names=$(safe_manifest_value "$BOOTSTRAP_ENV_NAMES")"
    echo "bootstrap_env_sha256=$BOOTSTRAP_ENV_SHA256"
    echo "cache_mode=$(safe_manifest_value "$CACHE_MODE")"
    echo "cache_mode_value_sha256=$CACHE_MODE_VALUE_SHA256"
    echo "allow_dirty=$(safe_manifest_value "$ALLOW_DIRTY")"
    echo "stages=$(safe_manifest_value "$STAGES")"
    echo "out_dir=$(safe_manifest_value "$OUT_DIR")"
    echo "hash_backend=$(safe_manifest_value "$HASH_BACKEND")"
    if [[ -z "$FIRST_FAIL" ]]; then
      echo "status=success"
    else
      echo "status=failed"
      echo "failed_stage=$(safe_manifest_value "$FIRST_FAIL")"
      echo "failed_kind=$(safe_manifest_value "$FIRST_FAIL_KIND")"
    fi

    for ((stage = 1; stage <= ${#ST_OK[@]}; stage++)); do
      echo "stage${stage}_status=$(safe_manifest_value "${ST_OK[$((stage - 1))]}")"
      echo "stage${stage}_producer=$(safe_manifest_value "${ST_PRODUCER[$stage]:-}")"
      echo "stage${stage}_producer_b64=$(base64_manifest_value "${ST_PRODUCER[$stage]:-}")"
      echo "stage${stage}_producer_sha256=$(safe_manifest_value "${ST_PRODUCER_HASH[$stage]:-unavailable}")"
      echo "stage${stage}_producer_hash=$(safe_manifest_value "${ST_PRODUCER_HASH[$stage]:-unavailable}")"
      echo "stage${stage}_producer_sha256_end=$(safe_manifest_value "${ST_PRODUCER_HASH_END[$stage]:-unavailable}")"
      echo "stage${stage}_producer_matches_previous_output=$(safe_manifest_value "${ST_PRODUCER_MATCH[$stage]:-unknown}")"
      echo "stage${stage}_output=$(safe_manifest_value "${ST_BIN[$((stage - 1))]:-}")"
      echo "stage${stage}_output_b64=$(base64_manifest_value "${ST_BIN[$((stage - 1))]:-}")"
      echo "stage${stage}_output_sha256=$(safe_manifest_value "${ST_OUTPUT_HASH[$stage]:-unavailable}")"
      echo "stage${stage}_output_hash=$(safe_manifest_value "${ST_OUTPUT_HASH[$stage]:-unavailable}")"
      echo "stage${stage}_output_sha256_end=$(safe_manifest_value "${ST_OUTPUT_HASH_END[$stage]:-unavailable}")"
      echo "stage${stage}_flags_b64=$(base64_manifest_value "${ST_FLAGS[$stage]:-}")"
      echo "stage${stage}_flags_text=$(safe_manifest_value "${ST_FLAGS[$stage]:-}")"
      echo "stage${stage}_build_started_at=$(safe_manifest_value "${ST_STARTED[$stage]:-}")"
      echo "stage${stage}_build_finished_at=$(safe_manifest_value "${ST_FINISHED[$stage]:-}")"
      echo "stage${stage}_build_time_sec=$(safe_manifest_value "${ST_WALL[$((stage - 1))]:-unknown}")"
      echo "stage${stage}_run_id=$(safe_manifest_value "$RUN_ID")"
      echo "stage${stage}_cache_mode=$(safe_manifest_value "$CACHE_MODE")"
      echo "stage${stage}_timeout_sec=$(safe_manifest_value "$TIMEOUT_SEC")"
      echo "stage${stage}_mem_mb=$(safe_manifest_value "$MEM_MB")"
      echo "stage${stage}_resource=$(safe_manifest_value "${ST_RESOURCE[$stage]:-unknown}")"
      echo "stage${stage}_smoke_plain=$(safe_manifest_value "${ST_SMOKE_P[$((stage - 1))]:--}")"
      echo "stage${stage}_smoke_plain_output_sha256=$(safe_manifest_value "${ST_SMOKE_P_HASH[$stage]:-unavailable}")"
      echo "stage${stage}_smoke_noprelude=$(safe_manifest_value "${ST_SMOKE_N[$((stage - 1))]:--}")"
      echo "stage${stage}_smoke_noprelude_output_sha256=$(safe_manifest_value "${ST_SMOKE_N_HASH[$stage]:-unavailable}")"
    done
  } >"$tmp_manifest" || return 1
  mv -f "$tmp_manifest" "$MANIFEST" || return 1
}

for ((s = 1; s <= STAGES; s++)); do
  OUT_BIN="$OUT_DIR/cv2_s${s}"
  LOG_B="$OUT_DIR/stage${s}_build.log"
  LOG_P="$OUT_DIR/stage${s}_smoke_plain.log"
  LOG_N="$OUT_DIR/stage${s}_smoke_noprelude.log"

  ST_BIN+=("$OUT_BIN")
  ST_STARTED[$s]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ST_FLAGS[$s]=""
  ST_FLAGS_B64[$s]=""
  ST_OUTPUT_HASH[$s]="missing"
  ST_OUTPUT_HASH_END[$s]="missing"
  ST_PRODUCER_HASH[$s]="unavailable"
  ST_PRODUCER_HASH_END[$s]="unavailable"
  ST_SMOKE_P_HASH[$s]="missing"
  ST_SMOKE_N_HASH[$s]="missing"

  if [[ $s -eq 1 ]]; then
    PRODUCER_PATH="$HOST_COMPILER_RESOLVED"
    ST_FLAGS[$s]="build ${SOURCE_REL} -o ${OUT_BIN} --error-trace"
  else
    PRODUCER_PATH="$(resolve_tool_path "$PREV")"
    ST_FLAGS[$s]="${SOURCE_REL} -o ${OUT_BIN}"
  fi
  ST_PRODUCER[$s]="$PRODUCER_PATH"
  ST_PRODUCER_HASH[$s]="$(sha256_file "$PRODUCER_PATH" || printf 'unavailable')"
  if [[ $s -eq 1 ]]; then
    ST_PRODUCER_MATCH[$s]="not_applicable"
  elif [[ "${ST_PRODUCER_HASH[$s]}" == "${ST_OUTPUT_HASH_END[$((s - 1))]}" ]]; then
    ST_PRODUCER_MATCH[$s]="yes"
  else
    ST_PRODUCER_MATCH[$s]="no"
  fi
  ST_FLAGS_B64[$s]="$(base64_manifest_value "${ST_FLAGS[$s]}")"

  if [[ $s -gt 1 && "${ST_PRODUCER_MATCH[$s]}" != "yes" ]]; then
    ST_FINISHED[$s]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ST_OK+=("fail")
    ST_WALL+=("?")
    ST_PEAK+=("?")
    ST_SMOKE_P+=("-")
    ST_SMOKE_N+=("-")
    ST_LOG+=("$LOG_B")
    FIRST_FAIL="$s"
    FIRST_FAIL_KIND="producer_mismatch"
    FIRST_SYMPTOM="stage producer hash does not match previous stage output hash"
    break
  fi

  # Never allow a producer to leave a prior path in place and receive credit
  # for it.  The preflight above protects reused directories; this per-stage
  # removal also covers artifacts created opportunistically by a prior stage.
  rm -f "$OUT_BIN"

  if [[ $s -eq 1 ]]; then
    echo "--- Stage $s (host build) ---"
    run_stage1_host "$OUT_BIN" "$LOG_B"
    RC=$?
    PREV="$OUT_BIN"
  else
    echo "--- Stage $s (self-host via cv2_s$((s - 1))) ---"
    run_stageN_selfhost "$PREV" "$OUT_BIN" "$LOG_B"
    RC=$?
    PREV="$OUT_BIN"
  fi

  ST_FINISHED[$s]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ST_PRODUCER_HASH_END[$s]="$(sha256_file "$PRODUCER_PATH" || printf 'unavailable')"
  ST_OUTPUT_HASH_END[$s]="$(sha256_file "$OUT_BIN" || printf 'missing')"
  ST_RESOURCE[$s]="$(parse_resource_summary "$LOG_B" || true)"
  if [[ -z "${ST_RESOURCE[$s]}" ]]; then
    ST_RESOURCE[$s]="unknown"
  fi

  WALL_REAL="$(parse_time_real "$LOG_B" || true)"
  RSS_B="$(parse_time_l_max_rss_bytes "$LOG_B" || true)"
  PEAK_MB="$(bytes_to_mb "$RSS_B")"

  if [[ $RC -ne 0 ]]; then
    ST_OK+=("fail")
    ST_WALL+=("${WALL_REAL:-?}")
    ST_PEAK+=("${PEAK_MB:-?}")
    ST_SMOKE_P+=("-")
    ST_SMOKE_N+=("-")
    ST_LOG+=("$LOG_B")
    if [[ -z "$FIRST_FAIL" ]]; then
      FIRST_FAIL="$s"
      FIRST_FAIL_KIND="build"
      FIRST_SYMPTOM="$(stderr_tail "$LOG_B" 40)"
    fi
    echo "STAGE $s BUILD: FAIL (exit $RC)"
    stderr_tail "$LOG_B" 50
    break
  fi

  if [[ ! -f "$OUT_BIN" || -L "$OUT_BIN" || ! -x "$OUT_BIN" || ! -s "$OUT_BIN" ]]; then
    ST_OK+=("fail")
    ST_WALL+=("${WALL_REAL:-?}")
    ST_PEAK+=("${PEAK_MB:-?}")
    ST_SMOKE_P+=("-")
    ST_SMOKE_N+=("-")
    ST_LOG+=("$LOG_B")
    if [[ -z "$FIRST_FAIL" ]]; then
      FIRST_FAIL="$s"
      FIRST_FAIL_KIND="missing_binary"
      FIRST_SYMPTOM="fresh stage artifact missing, empty, or non-regular after exit 0: $OUT_BIN"
    fi
    echo "STAGE $s: fresh stage artifact missing, empty, or non-regular after exit 0"
    break
  fi

  ST_OUTPUT_HASH[$s]="$(sha256_file "$OUT_BIN" || printf 'missing')"

  echo "STAGE $s BUILD: ok  wall=${WALL_REAL:-?}s  peak_rss≈${PEAK_MB:-?}MB  -> $OUT_BIN"

  SP_OK="ok"
  SN_OK="ok"
  run_smoke_plain "$OUT_BIN" "$LOG_P"
  RCP=$?
  if [[ $RCP -ne 0 ]]; then
    SP_OK="fail"
    if [[ -z "$FIRST_FAIL" ]]; then
      FIRST_FAIL="$s"
      FIRST_FAIL_KIND="smoke_plain"
      FIRST_SYMPTOM="$(stderr_tail "$LOG_P" 40)"
    fi
  fi
  run_smoke_noprelude "$OUT_BIN" "$LOG_N"
  RCN=$?
  if [[ $RCN -ne 0 ]]; then
    SN_OK="fail"
    if [[ -z "$FIRST_FAIL" ]]; then
      FIRST_FAIL="$s"
      FIRST_FAIL_KIND="smoke_noprelude"
      FIRST_SYMPTOM="$(stderr_tail "$LOG_N" 40)"
    fi
  fi

  ST_OK+=("ok")
  ST_WALL+=("${WALL_REAL:-?}")
  ST_PEAK+=("${PEAK_MB:-?}")
  ST_SMOKE_P+=("$SP_OK")
  ST_SMOKE_N+=("$SN_OK")
  ST_LOG+=("$LOG_B")
  if [[ -f "$OUT_DIR/_smoke_puts42.bin" && ! -L "$OUT_DIR/_smoke_puts42.bin" ]]; then
    ST_SMOKE_P_HASH[$s]="$(sha256_file "$OUT_DIR/_smoke_puts42.bin" || printf 'missing')"
  fi
  if [[ -f "$OUT_DIR/_smoke_noprel.bin" && ! -L "$OUT_DIR/_smoke_noprel.bin" ]]; then
    ST_SMOKE_N_HASH[$s]="$(sha256_file "$OUT_DIR/_smoke_noprel.bin" || printf 'missing')"
  fi

  echo "  smoke plain:     $SP_OK"
  echo "  smoke no-prelude: $SN_OK"
  if [[ "$SP_OK" != "ok" ]]; then
    stderr_tail "$LOG_P" 30
  fi
  if [[ "$SN_OK" != "ok" ]]; then
    stderr_tail "$LOG_N" 30
  fi

  if [[ "$SP_OK" != "ok" || "$SN_OK" != "ok" ]]; then
    break
  fi

  ST_PRODUCER_HASH_END[$s]="$(sha256_file "$PRODUCER_PATH" || printf 'unavailable')"
  ST_OUTPUT_HASH_END[$s]="$(sha256_file "$OUT_BIN" || printf 'missing')"
  if [[ "${ST_PRODUCER_HASH_END[$s]}" != "${ST_PRODUCER_HASH[$s]}" ||
        "${ST_OUTPUT_HASH_END[$s]}" != "${ST_OUTPUT_HASH[$s]}" ]]; then
    if [[ -z "$FIRST_FAIL" ]]; then
      FIRST_FAIL="$s"
      FIRST_FAIL_KIND="producer_or_output_mutated"
      FIRST_SYMPTOM="stage producer or output changed after smoke verification"
    fi
    ST_OK[$((${#ST_OK[@]} - 1))]="fail"
    break
  fi
done

# Re-hash the source after the ladder.  A producer that mutates the source
# during a run must not receive a manifest claiming one coherent input tree.
SOURCE_CONTENT_SHA256_END="$(sha256_file "$SOURCE_ABS" || true)"
SOURCE_TREE_SHA256_END="$(hash_source_tree || true)"
if [[ "$SOURCE_CONTENT_SHA256_END" == "$SOURCE_CONTENT_SHA256" &&
      "$SOURCE_TREE_SHA256_END" == "$SOURCE_TREE_SHA256" ]]; then
  SOURCE_HASH_CONSISTENT=1
else
  SOURCE_HASH_CONSISTENT=0
  if [[ -z "$FIRST_FAIL" ]]; then
    FIRST_FAIL="source"
    FIRST_FAIL_KIND="source_mutated"
    FIRST_SYMPTOM="bootstrap source content changed during the run"
  fi
fi

echo ""
echo "================================================================"
echo "SUMMARY"
echo "================================================================"

printf "%-6s %-8s %-10s %-12s %-12s %-12s %s\n" \
  "Stage" "Build" "Wall(s)" "PeakRSS(MB)" "Smoke+" "SmokeNP" "Binary"
for ((i = 0; i < ${#ST_OK[@]}; i++)); do
  sn=$((i + 1))
  printf "%-6s %-8s %-10s %-12s %-12s %-12s %s\n" \
    "s${sn}" "${ST_OK[$i]}" "${ST_WALL[$i]}" "${ST_PEAK[$i]}" "${ST_SMOKE_P[$i]}" "${ST_SMOKE_N[$i]}" "${ST_BIN[$i]}"
done

echo ""
if [[ -n "$FIRST_FAIL" ]]; then
  if ! write_manifest; then
    echo "error: unable to write bootstrap provenance manifest: $MANIFEST" >&2
    exit 1
  fi
  echo "Earliest failing stage: $FIRST_FAIL ($FIRST_FAIL_KIND)"
  echo "First symptom:"
  echo "$FIRST_SYMPTOM"
  echo ""
  echo "Logs under: $OUT_DIR"
  exit 1
fi

LAST_IDX=$((${#ST_OK[@]} - 1))
if [[ ${#ST_OK[@]} -eq "$STAGES" ]] && [[ "${ST_OK[$LAST_IDX]:-}" == "ok" ]]; then
  if ! write_manifest; then
    echo "error: unable to write bootstrap provenance manifest: $MANIFEST" >&2
    exit 1
  fi
  echo "Bootstrap ladder: ALL GREEN through stage ${STAGES} (s${STAGES} landmark)."
  echo "Logs under: $OUT_DIR"
  exit 0
fi

echo "Incomplete ladder (expected $STAGES stages, recorded ${#ST_OK[@]})."
if ! write_manifest; then
  echo "error: unable to write bootstrap provenance manifest: $MANIFEST" >&2
  exit 1
fi
echo "Logs under: $OUT_DIR"
exit 1
