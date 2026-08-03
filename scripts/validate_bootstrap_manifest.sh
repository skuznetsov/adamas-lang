#!/usr/bin/env bash
# Offline B4-F readiness validator for a bootstrap_chain_v3 run directory.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
source "$ROOT_DIR/scripts/lib/bootstrap_evidence_contract.sh"
RUN_DIR=""
EXPECTED_HOST=""
MAX_STAGE2_WALL_SEC="300"

usage() {
  cat <<'USAGE'
Usage:
  scripts/validate_bootstrap_manifest.sh --run-dir DIR --expected-host PATH
      [--max-stage2-wall-sec SEC]

The validator is read-only. It rehashes the source, harness, trusted host,
stage lineage, build/resource evidence, and exact smoke transcripts before
applying the normal-build, numeric-resource, and stage2 wall-time policies.
USAGE
}

reject() {
  echo "bootstrap_manifest_rejected reason=$1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      [[ $# -ge 2 ]] || reject "usage"
      RUN_DIR="$2"
      shift 2
      ;;
    --expected-host)
      [[ $# -ge 2 ]] || reject "usage"
      EXPECTED_HOST="$2"
      shift 2
      ;;
    --max-stage2-wall-sec)
      [[ $# -ge 2 ]] || reject "usage"
      MAX_STAGE2_WALL_SEC="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      reject "usage"
      ;;
  esac
done

[[ -n "$RUN_DIR" && -n "$EXPECTED_HOST" ]] || reject "usage"
[[ "$MAX_STAGE2_WALL_SEC" =~ ^[0-9]+([.][0-9][0-9]?)?$ ]] || reject "stage2_wall_policy"
awk -v value="$MAX_STAGE2_WALL_SEC" 'BEGIN { exit !(value > 0 && value <= 300) }' || reject "stage2_wall_policy"
[[ -d "$RUN_DIR" && ! -L "$RUN_DIR" ]] || reject "run_directory"
RUN_DIR="$(cd "$RUN_DIR" && pwd -P)" || reject "run_directory"
case "$RUN_DIR" in
  "$ROOT_DIR/src"|"$ROOT_DIR/src"/*) reject "run_directory" ;;
esac
MANIFEST="$RUN_DIR/bootstrap_chain.manifest"

if command -v shasum >/dev/null 2>&1; then
  HASH_BACKEND="shasum"
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_BACKEND="sha256sum"
else
  reject "hash_backend"
fi

sha256_file() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  if [[ "$HASH_BACKEND" == "shasum" ]]; then
    shasum -a 256 -- "$path" | awk '{print $1}'
  else
    sha256sum -- "$path" | awk '{print $1}'
  fi
}

sha256_text() {
  if [[ "$HASH_BACKEND" == "shasum" ]]; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  fi
}

hash_source_tree() {
  (
    cd "$ROOT_DIR" || exit 1
    if [[ "$HASH_BACKEND" == "shasum" ]]; then
      find src -type f -exec shasum -a 256 {} + 2>/dev/null | LC_ALL=C sort | shasum -a 256 | awk '{print $1}'
    else
      find src -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort | sha256sum | awk '{print $1}'
    fi
  )
}

valid_evidence_file() {
  [[ -f "$1" && ! -L "$1" && -s "$1" && "$(bootstrap_file_nlink "$1")" == "1" ]]
}

valid_executable() {
  valid_evidence_file "$1" && [[ -x "$1" ]]
}

valid_sha256() {
  [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

valid_evidence_file "$MANIFEST" || reject "manifest_shape"
awk '
  index($0, "=") < 2 { bad = 1; next }
  {
    key = substr($0, 1, index($0, "=") - 1)
    if (key !~ /^[A-Za-z][A-Za-z0-9_]*$/ || seen[key]++) bad = 1
  }
  END { exit (NR > 0 && !bad) ? 0 : 1 }
' "$MANIFEST" || reject "manifest_shape"

manifest_value() {
  local key="$1"
  awk -v wanted="$key" '
    index($0, "=") > 0 {
      key = substr($0, 1, index($0, "=") - 1)
      if (key == wanted) print substr($0, index($0, "=") + 1)
    }
  ' "$MANIFEST"
}

require_value() {
  [[ "$(manifest_value "$1")" == "$2" ]]
}

require_sha_field() {
  local value
  value="$(manifest_value "$1")"
  valid_sha256 "$value"
}

decode_base64() {
  local encoded="$1"
  local decoded
  decoded="$(printf '%s' "$encoded" | base64 --decode 2>/dev/null)" ||
    decoded="$(printf '%s' "$encoded" | base64 -D 2>/dev/null)" || return 1
  printf '%s' "$decoded"
}

resolve_tool_path() {
  local found
  if [[ "$1" == */* ]]; then
    found="$1"
  else
    found="$(command -v "$1" 2>/dev/null)" || return 1
  fi
  realpath "$found" 2>/dev/null
}

resource_ready() {
  local resource_file="$1"
  local numeric_field
  local max_rss max_fd rss_samples fd_samples tree_samples stable_samples unstable_samples max_tree_pids
  bootstrap_exact_success_resource_file "$resource_file" || return 1
  [[ "$(bootstrap_resource_field schema "$resource_file")" == "run_safe_resource_v1" ]] || return 1
  [[ "$(bootstrap_resource_field outcome "$resource_file")" == "exit" ]] || return 1
  [[ "$(bootstrap_resource_field reason "$resource_file")" == "exit" ]] || return 1
  [[ "$(bootstrap_resource_field exit_code "$resource_file")" == "0" ]] || return 1
  [[ "$(bootstrap_resource_field rss_available "$resource_file")" == "yes" ]] || return 1
  [[ "$(bootstrap_resource_field fd_available "$resource_file")" == "yes" ]] || return 1
  [[ "$(bootstrap_resource_field process_tree_mode "$resource_file")" == "ps_ancestry_snapshot" ]] || return 1
  [[ "$(bootstrap_resource_field tree_coverage "$resource_file")" == "all_scheduled_snapshots" ]] || return 1
  [[ "$(bootstrap_resource_field fd_tree_coverage "$resource_file")" == "all_stable_pairs" ]] || return 1
  for numeric_field in max_rss_kb max_fd rss_samples fd_samples tree_samples fd_topology_stable_samples fd_topology_unstable_samples max_tree_pids; do
    [[ "$(bootstrap_resource_field "$numeric_field" "$resource_file")" =~ ^[0-9]+$ ]] || return 1
  done
  max_rss="$(bootstrap_resource_field max_rss_kb "$resource_file")"
  max_fd="$(bootstrap_resource_field max_fd "$resource_file")"
  rss_samples="$(bootstrap_resource_field rss_samples "$resource_file")"
  fd_samples="$(bootstrap_resource_field fd_samples "$resource_file")"
  tree_samples="$(bootstrap_resource_field tree_samples "$resource_file")"
  stable_samples="$(bootstrap_resource_field fd_topology_stable_samples "$resource_file")"
  unstable_samples="$(bootstrap_resource_field fd_topology_unstable_samples "$resource_file")"
  max_tree_pids="$(bootstrap_resource_field max_tree_pids "$resource_file")"
  [[ "$max_rss" -gt 0 && "$max_fd" -gt 0 && "$tree_samples" -gt 0 && "$max_tree_pids" -gt 0 ]] || return 1
  [[ "$rss_samples" == "$tree_samples" ]] || return 1
  [[ "$fd_samples" == "$tree_samples" ]] || return 1
  [[ "$stable_samples" == "$tree_samples" ]] || return 1
  [[ "$unstable_samples" == "0" ]]
}

check_named_artifact() {
  local rel_field="$1"
  local expected_rel="$2"
  local hash_field="$3"
  local kind="$4"
  local path="$RUN_DIR/$expected_rel"
  local expected_hash
  require_value "$rel_field" "$expected_rel" || return 1
  expected_hash="$(manifest_value "$hash_field")"
  valid_sha256 "$expected_hash" || return 1
  if [[ "$kind" == "executable" ]]; then
    valid_executable "$path" || return 1
  else
    valid_evidence_file "$path" || return 1
  fi
  [[ "$(sha256_file "$path")" == "$expected_hash" ]]
}

require_value manifest_schema bootstrap_chain_v3 || reject "manifest_shape"
require_value status success || reject "manifest_status"
require_value requested_stages 2 || reject "manifest_status"
require_value recorded_stages 2 || reject "manifest_status"
require_value failed_stage none || reject "manifest_status"
require_value failed_kind none || reject "manifest_status"

SOURCE_REL="$(decode_base64 "$(manifest_value source_rel_b64)")" || reject "manifest_shape"
SOURCE_SCOPE_REL="$(decode_base64 "$(manifest_value source_scope_rel_b64)")" || reject "manifest_shape"
[[ "$SOURCE_REL" == "src/adamas.cr" && "$SOURCE_SCOPE_REL" == "src" ]] || reject "source_or_harness_identity"
require_value source_consistency_model endpoint_before_after || reject "source_or_harness_identity"
require_value source_hash_consistent 1 || reject "source_or_harness_identity"

SOURCE_FILE_HASH="$(sha256_file "$ROOT_DIR/src/adamas.cr")" || reject "source_or_harness_identity"
SOURCE_TREE_HASH="$(hash_source_tree)" || reject "source_or_harness_identity"
[[ -z "$(find "$ROOT_DIR/src" -type l -print -quit 2>/dev/null)" ]] || reject "source_or_harness_identity"
[[ "$(manifest_value source_content_sha256_start)" == "$SOURCE_FILE_HASH" ]] || reject "source_or_harness_identity"
[[ "$(manifest_value source_content_sha256_end)" == "$SOURCE_FILE_HASH" ]] || reject "source_or_harness_identity"
[[ "$(manifest_value source_tree_sha256_start)" == "$SOURCE_TREE_HASH" ]] || reject "source_or_harness_identity"
[[ "$(manifest_value source_tree_sha256_end)" == "$SOURCE_TREE_HASH" ]] || reject "source_or_harness_identity"

CURRENT_GIT_HEAD="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null)" || reject "source_or_harness_identity"
CURRENT_SOURCE_STATUS="$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all -- src 2>/dev/null || true)"
CURRENT_SOURCE_DIFF="$(git -C "$ROOT_DIR" diff --no-ext-diff --binary -- src 2>/dev/null || true)"
[[ "$(manifest_value source_git_head)" == "$CURRENT_GIT_HEAD" ]] || reject "source_or_harness_identity"
[[ "$(manifest_value source_git_status_sha256)" == "$(sha256_text "$CURRENT_SOURCE_STATUS")" ]] || reject "source_or_harness_identity"
[[ "$(manifest_value source_git_diff_sha256)" == "$(sha256_text "$CURRENT_SOURCE_DIFF")" ]] || reject "source_or_harness_identity"
[[ "$(manifest_value harness_bootstrap_chain_sha256)" == "$(sha256_file "$ROOT_DIR/scripts/bootstrap_chain.sh")" ]] || reject "source_or_harness_identity"
[[ "$(manifest_value harness_run_safe_sha256)" == "$(sha256_file "$ROOT_DIR/scripts/run_safe.sh")" ]] || reject "source_or_harness_identity"
[[ "$(manifest_value harness_evidence_contract_sha256)" == "$(sha256_file "$ROOT_DIR/scripts/lib/bootstrap_evidence_contract.sh")" ]] || reject "source_or_harness_identity"

require_value smoke_plain_source_rel _smoke_puts42.cr || reject "smoke_input_identity"
valid_evidence_file "$RUN_DIR/_smoke_puts42.cr" || reject "smoke_input_identity"
PLAIN_SMOKE_SHA256="$(sha256_file "$RUN_DIR/_smoke_puts42.cr")" || reject "smoke_input_identity"
[[ "$PLAIN_SMOKE_SHA256" == "$(manifest_value smoke_plain_source_sha256)" ]] || reject "smoke_input_identity"
[[ "$PLAIN_SMOKE_SHA256" == "$(sha256_text $'puts 42\n')" ]] || reject "smoke_input_identity"
require_value smoke_noprelude_oracle_rel regression_tests/combined/test_no_prelude_interpolation.cr || reject "smoke_input_identity"
NO_PRELUDE_ORACLE="$ROOT_DIR/regression_tests/combined/test_no_prelude_interpolation.cr"
valid_evidence_file "$NO_PRELUDE_ORACLE" || reject "smoke_input_identity"
[[ "$(realpath "$NO_PRELUDE_ORACLE" 2>/dev/null)" == "$NO_PRELUDE_ORACLE" ]] || reject "smoke_input_identity"
NO_PRELUDE_ORACLE_SHA256="$(sha256_file "$NO_PRELUDE_ORACLE")" || reject "smoke_input_identity"
[[ "$(manifest_value smoke_noprelude_oracle_sha256_start)" == "$NO_PRELUDE_ORACLE_SHA256" ]] || reject "smoke_input_identity"
[[ "$(manifest_value smoke_noprelude_oracle_sha256_end)" == "$NO_PRELUDE_ORACLE_SHA256" ]] || reject "smoke_input_identity"

EXPECTED_HOST="$(resolve_tool_path "$EXPECTED_HOST")" || reject "host_identity"
valid_executable "$EXPECTED_HOST" || reject "host_identity"
MANIFEST_HOST="$(decode_base64 "$(manifest_value host_compiler_b64)")" || reject "host_identity"
[[ "$MANIFEST_HOST" == "$EXPECTED_HOST" ]] || reject "host_identity"
EXPECTED_HOST_SHA256="$(sha256_file "$EXPECTED_HOST")" || reject "host_identity"
[[ "$(manifest_value host_compiler_sha256)" == "$EXPECTED_HOST_SHA256" ]] || reject "host_identity"

require_value run_directory_policy producer_created_absent_path || reject "run_directory"
require_value cache_policy producer_created_empty || reject "run_directory"
require_value cache_dir_rel cache || reject "run_directory"
[[ "$(bootstrap_directory_mode "$RUN_DIR")" == "700" ]] || reject "run_directory"
[[ "$(manifest_value run_directory_identity)" == "$(bootstrap_directory_identity "$RUN_DIR")" ]] || reject "run_directory"
[[ -d "$RUN_DIR/cache" && ! -L "$RUN_DIR/cache" ]] || reject "run_directory"
[[ "$(bootstrap_directory_mode "$RUN_DIR/cache")" == "700" ]] || reject "run_directory"
[[ "$(manifest_value cache_directory_identity)" == "$(bootstrap_directory_identity "$RUN_DIR/cache")" ]] || reject "run_directory"

for context_field in environment_path_sha256 environment_home_sha256 environment_tmpdir_sha256 compiler_environment_sanitized_names_sha256; do
  require_sha_field "$context_field" || reject "build_policy"
done
require_value compiler_environment_policy known_controls_unset || reject "build_policy"
require_value worker_policy crystal_workers_unset || reject "build_policy"

for stage in 1 2; do
  STAGE_WALL_SEC="$(manifest_value "stage${stage}_build_wall_sec")"
  [[ "$STAGE_WALL_SEC" =~ ^[0-9]+([.][0-9][0-9]?)?$ ]] || reject "build_policy"
  require_value "stage${stage}_status" ok || reject "manifest_status"
  require_value "stage${stage}_build_mode" normal_binary || reject "build_policy"
  require_value "stage${stage}_output_rel" "cv2_s${stage}" || reject "artifact_hash"
  require_value "stage${stage}_resource_schema" run_safe_resource_v1 || reject "resource_coverage"
  require_value "stage${stage}_smoke_plain_status" ok || reject "smoke_transcript"
  require_value "stage${stage}_smoke_plain_expected" 42 || reject "smoke_transcript"
  require_value "stage${stage}_smoke_noprelude_status" ok || reject "smoke_transcript"
  require_value "stage${stage}_smoke_noprelude_expected" noprelude_interp_ok || reject "smoke_transcript"

  check_named_artifact "stage${stage}_output_rel" "cv2_s${stage}" "stage${stage}_output_sha256" executable || reject "artifact_hash"
  [[ "$(manifest_value "stage${stage}_output_sha256_end")" == "$(manifest_value "stage${stage}_output_sha256")" ]] || reject "artifact_hash"
  check_named_artifact "stage${stage}_build_log_rel" "stage${stage}_build.log" "stage${stage}_build_log_sha256" evidence || reject "artifact_hash"
  check_named_artifact "stage${stage}_resource_rel" "stage${stage}_build.resource" "stage${stage}_resource_sha256" evidence || reject "artifact_hash"
  check_named_artifact "stage${stage}_smoke_plain_binary_rel" "stage${stage}_smoke_plain.bin" "stage${stage}_smoke_plain_binary_sha256" executable || reject "artifact_hash"
  check_named_artifact "stage${stage}_smoke_plain_compile_log_rel" "stage${stage}_smoke_plain.log" "stage${stage}_smoke_plain_compile_log_sha256" evidence || reject "artifact_hash"
  check_named_artifact "stage${stage}_smoke_plain_runtime_log_rel" "stage${stage}_smoke_plain.runtime.log" "stage${stage}_smoke_plain_log_sha256" evidence || reject "artifact_hash"
  check_named_artifact "stage${stage}_smoke_noprelude_binary_rel" "stage${stage}_smoke_noprelude.bin" "stage${stage}_smoke_noprelude_binary_sha256" executable || reject "artifact_hash"
  check_named_artifact "stage${stage}_smoke_noprelude_compile_log_rel" "stage${stage}_smoke_noprelude.log" "stage${stage}_smoke_noprelude_compile_log_sha256" evidence || reject "artifact_hash"
  check_named_artifact "stage${stage}_smoke_noprelude_runtime_log_rel" "stage${stage}_smoke_noprelude.runtime.log" "stage${stage}_smoke_noprelude_log_sha256" evidence || reject "artifact_hash"

  [[ "$(bootstrap_build_wall "$RUN_DIR/stage${stage}_build.log")" == "$STAGE_WALL_SEC" ]] || reject "stage_wall_evidence"
  resource_ready "$RUN_DIR/stage${stage}_build.resource" || reject "resource_coverage"
  [[ "$(bootstrap_build_resource_row "$RUN_DIR/stage${stage}_build.log")" == "$(sed -n '1p' "$RUN_DIR/stage${stage}_build.resource")" ]] || reject "resource_coverage"
  bootstrap_exact_smoke_transcript "$RUN_DIR/stage${stage}_smoke_plain.runtime.log" 42 || reject "smoke_transcript"
  bootstrap_exact_smoke_transcript "$RUN_DIR/stage${stage}_smoke_noprelude.runtime.log" noprelude_interp_ok || reject "smoke_transcript"
done

require_value stage1_flags_b64 "$(printf '%s' 'build src/adamas.cr -o cv2_s1 --error-trace' | base64 | tr -d '\r\n')" || reject "build_policy"
require_value stage2_flags_b64 "$(printf '%s' 'src/adamas.cr -o cv2_s2' | base64 | tr -d '\r\n')" || reject "build_policy"
require_value stage1_producer_matches_previous_output not_applicable || reject "producer_lineage"
require_value stage2_producer_matches_previous_output yes || reject "producer_lineage"
[[ "$(manifest_value stage1_producer_sha256)" == "$EXPECTED_HOST_SHA256" ]] || reject "producer_lineage"
[[ "$(manifest_value stage1_producer_sha256_end)" == "$EXPECTED_HOST_SHA256" ]] || reject "producer_lineage"
STAGE1_OUTPUT_SHA256="$(manifest_value stage1_output_sha256_end)"
[[ "$(manifest_value stage2_producer_sha256)" == "$STAGE1_OUTPUT_SHA256" ]] || reject "producer_lineage"
[[ "$(manifest_value stage2_producer_sha256_end)" == "$STAGE1_OUTPUT_SHA256" ]] || reject "producer_lineage"

STAGE2_WALL_SEC="$(manifest_value stage2_build_wall_sec)"
awk -v actual="$STAGE2_WALL_SEC" -v maximum="$MAX_STAGE2_WALL_SEC" 'BEGIN { exit !(actual <= maximum) }' || reject "stage2_wall_budget"

echo "bootstrap_manifest_ready schema=bootstrap_chain_v3 stages=2 stage2_wall_sec=$STAGE2_WALL_SEC max_stage2_wall_sec=$MAX_STAGE2_WALL_SEC"
