#!/usr/bin/env bash
# T8 RED matrix. Child mode is an injected fake chain runner; it writes only
# current bootstrap_chain-style shell stubs/logs, never Crystal binaries.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="${T8_VALIDATOR:-$ROOT_DIR/scripts/t8_fresh_s2_readiness_validator.sh}"
KEEP_TMP="${KEEP_TMP:-0}"
MAX_LOG_BYTES="${T8_MAX_LOG_BYTES:-8388608}"

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'
  fi
}
write_stub() {
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$1"
  chmod +x "$1"
}
write_runtime() {
  local path="$1" mode="$2" variant="${3:-exact}"
  printf '=== STDOUT ===\n' >"$path"
  case "$mode:$variant" in
    plain:exact) printf '42\n' >>"$path" ;;
    plain:stderr) printf '42\n' >>"$path" ;;
    plain:forged) printf '42\n' >>"$path" ;;
    plain:extra) printf '42\nEXTRA\n' >>"$path" ;;
    plain:wrong) printf '41\n' >>"$path" ;;
    noprelude:exact) printf 'hello world\nn=42\nnoprelude_interp_ok\n' >>"$path" ;;
    noprelude:extra) printf 'hello world\nn=42\nnoprelude_interp_ok\nEXTRA\n' >>"$path" ;;
    noprelude:wrong) printf 'hello world\nn=41\nnoprelude_interp_ok\n' >>"$path" ;;
    *) printf 'unexpected\n' >>"$path" ;;
  esac
  printf '=== STDERR ===\n' >>"$path"
  if [[ "$variant" == stderr ]]; then printf 'child-noise\n' >>"$path"; fi
  # Match the canonical run_safe transcript: the wrapper's exit diagnostic is
  # emitted after the captured child stdout/stderr sections.
  printf '[EXIT: 0] after ~0s\n' >>"$path"
  if [[ "$variant" == forged ]]; then sed -i '' 's/after ~0s/after forged/' "$path"; fi
}

fake_chain() {
  local out="" src="" case_name="${T8_FAKE_CASE:-at_180}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out) out="$2"; shift 2 ;;
      --source) src="$2"; shift 2 ;;
      --stages|--timeout|--mem) shift 2 ;;
      *) shift ;;
    esac
  done
  out="${T8_FAKE_OUTPUT:-$out}"
  src="${T8_FAKE_SOURCE:-$src}"
  [[ -n "$out" && -n "$src" ]] || { echo 'fake chain missing paths' >&2; return 2; }
  mkdir -p "$out"

  local s1="$out/cv2_s1" s2="$out/cv2_s2"
  write_stub "$s1"
  local s1h="$(sha256_file "$s1")"
  local rc=0 inner_rc=0 timeout=0 wall=180000 have_resource=1 partial_resource=0 have_s2=1
  local resource_outcome=success resource_reason=completed
  local plain=pass noprelude=pass pvar=exact nvar=exact
  local cache_mode=cold cache_identity=fake-cache parent="$s1h"
  case "$case_name" in
    at_180) ;;
    over_180) wall=180001 ;;
    missing_resource) have_resource=0 ;;
    malformed_resource) wall=bad ;;
    duplicate_resource|zero_resource|bogus_tree_mode|incomplete_tree|tree_sample_mismatch) ;;
    partial_resource) partial_resource=1 ;;
    explicit_timeout) rc=1 inner_rc=143 timeout=1 wall=180001 resource_outcome=timeout resource_reason=timeout have_s2=0 plain=unavailable noprelude=unavailable ;;
    ambiguous_rc143) rc=1 inner_rc=143 resource_outcome=failed resource_reason=exit_143 have_s2=0 plain=unavailable noprelude=unavailable ;;
    no_stage2) have_s2=0 ;;
    nested_s2_symlink) ;;
    plain_only) noprelude=unavailable ;;
    no_prelude_only) plain=unavailable ;;
    wrong_output) pvar=wrong ;;
    extra_output) nvar=extra ;;
    stderr_output) pvar=stderr ;;
    warm_cache) cache_mode=warm ;;
    cache_contradiction) cache_identity=stale ;;
    source_mutation) ;;
    provenance_contradiction) parent=wrong-parent ;;
    output_cap) ;;
    forged_diagnostic) pvar=forged ;;
    stage2_log_symlink|runtime_log_symlink|runner_log_overflow|runtime_log_overflow) ;;
    hang) ;;
    dirty_source_valid) ;;
    *) echo "unknown fake case: $case_name" >&2; return 2 ;;
  esac

  if [[ "$have_s2" == 1 ]]; then
    if [[ "$case_name" == nested_s2_symlink ]]; then
      write_stub "$out/cv2_s2.real"
      ln -s cv2_s2.real "$s2"
    else
      write_stub "$s2"
    fi
  fi
  local s2h=missing
  if [[ -f "$s2" ]]; then s2h="$(sha256_file "$s2")"; fi
  local s1log="$out/stage1_build.log" s2log="$out/stage2_build.log"
  printf '%s\n' '[EXIT: 0]' >"$s1log"
  printf '%s\n' '[EXIT: 0]' >"$out/stage1_smoke_plain.log"
  printf '%s\n' '[EXIT: 0]' >"$out/stage1_smoke_noprelude.log"
  if [[ "$timeout" -eq 1 ]]; then
    printf '%s\n' '[KILL] Timeout after 180s' '[EXIT: 143]' >"$s2log"
  elif [[ "$inner_rc" -eq 143 ]]; then
    printf '%s\n' '[EXIT: 143]' >"$s2log"
  else
    printf '%s\n' "[EXIT: $rc]" >"$s2log"
  fi

  if [[ "$have_s2" == 1 ]]; then
    local plog="$out/stage2_smoke_plain.log" nlog="$out/stage2_smoke_noprelude.log"
    printf '%s\n' '[EXIT: 0]' >"$plog"
    printf '%s\n' '[EXIT: 0]' >"$nlog"
    if [[ "$plain" == pass ]]; then write_runtime "$out/_smoke_puts42.runtime.log" plain "$pvar"; fi
    if [[ "$noprelude" == pass ]]; then write_runtime "$out/_smoke_noprel.runtime.log" noprelude "$nvar"; fi
  fi

  if [[ "$case_name" == output_cap ]]; then
    : >"$s2log"
    local i=0
    while [[ "$i" -lt 2048 ]]; do printf X >>"$s2log"; i=$((i + 1)); done
    printf '\n' >>"$s2log"
  fi
  if [[ "$case_name" == runner_log_overflow ]]; then
    printf '%2048s\n' X
  fi
  if [[ "$wall" == bad ]]; then
    printf '%s\n' 'real bad' >>"$s2log"
  else
    printf 'real %s\n' "$(awk -v ms="$wall" 'BEGIN { printf "%.3f", ms / 1000.0 }')" >>"$s2log"
  fi
  if [[ "$have_resource" == 1 ]]; then
    if [[ "$partial_resource" == 1 ]]; then
      printf '%s\n' '[RESOURCE] schema=t8_resource_v1 outcome=partial reason=incomplete exit_code=0 max_rss_kb=131072' >>"$s2log"
    else
      local resource_line
      resource_line="[RESOURCE] schema=t8_resource_v1 outcome=$resource_outcome reason=$resource_reason exit_code=$inner_rc max_rss_kb=131072 max_fd=64 rss_samples=2 fd_samples=2 rss_available=yes fd_available=yes process_tree_mode=pgid tree_coverage=complete tree_samples=2 tree_complete_samples=2 tree_incomplete_samples=0 max_tree_pids=1"
      case "$case_name" in
        duplicate_resource) printf '%s\n%s\n' "$resource_line" "$resource_line" >>"$s2log" ;;
        zero_resource) resource_line="${resource_line/max_rss_kb=131072/max_rss_kb=0}"; resource_line="${resource_line/max_fd=64/max_fd=0}"; printf '%s\n' "$resource_line" >>"$s2log" ;;
        bogus_tree_mode) resource_line="${resource_line/process_tree_mode=pgid/process_tree_mode=bogus}"; printf '%s\n' "$resource_line" >>"$s2log" ;;
        incomplete_tree) resource_line="${resource_line/tree_incomplete_samples=0/tree_incomplete_samples=1}"; printf '%s\n' "$resource_line" >>"$s2log" ;;
        tree_sample_mismatch) resource_line="${resource_line/tree_complete_samples=2/tree_complete_samples=1}"; printf '%s\n' "$resource_line" >>"$s2log" ;;
        *) printf '%s\n' "$resource_line" >>"$s2log" ;;
      esac
    fi
  fi
  if [[ "$cache_mode" != cold || "$case_name" == cache_contradiction ]]; then
    printf '[CACHE] cache_mode=%s cache_identity=%s\n' "$cache_mode" "$cache_identity" >>"$s2log"
  fi
  if [[ "$case_name" == provenance_contradiction ]]; then
    printf '[LINEAGE] stage2_parent_sha256=wrong-parent\n' >>"$s2log"
  fi
  if [[ "$case_name" == source_mutation ]]; then printf '%s\n' mutated >>"$src"; fi
  printf '[PROVENANCE] stage1_sha256=%s stage2_sha256=%s parent_sha256=%s\n' \
    "$s1h" "$s2h" "$parent" >>"$s2log"
  if [[ "$case_name" == dirty_source_valid ]]; then
    printf '%s\n' '[PROVENANCE] source_dirty=1 patch_sha256=fake' >>"$s2log"
  fi
  if [[ "$case_name" == runtime_log_overflow ]]; then
    printf '%2048s\n' X >>"$out/_smoke_puts42.runtime.log"
  fi
  if [[ "$case_name" == stage2_log_symlink ]]; then
    mv "$s2log" "$s2log.real"; ln -s stage2_build.log.real "$s2log"
  elif [[ "$case_name" == runtime_log_symlink ]]; then
    mv "$out/_smoke_puts42.runtime.log" "$out/_smoke_puts42.runtime.log.real"
    ln -s _smoke_puts42.runtime.log.real "$out/_smoke_puts42.runtime.log"
  fi
  if [[ "$case_name" == hang ]]; then
    printf '%s\n' "$$" >"$out/fake.pid"
    trap 'rm -f "$out/fake.pid"' EXIT
    trap 'exit 143' TERM INT
    sleep 5
    rm -f "$out/fake.pid"
  fi
  return "$rc"
}

if [[ "${T8_FAKE_CHAIN_CHILD:-0}" == 1 ]]; then fake_chain "$@"; exit $?; fi
if [[ ! "$MAX_LOG_BYTES" =~ ^[1-9][0-9]*$ ]]; then
  echo t8.schema=t8_fresh_s2_v1; echo T8_STATUS=ERROR; echo T8_CLASSIFICATION=invalid_log_cap; exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas-t8-fake.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" == 1 ]] && echo "T8_FAKE_TMP_DIR=$WORK_DIR" >&2 || rm -rf "$WORK_DIR"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
CASES="$WORK_DIR/cases"; mkdir -p "$CASES"
echo t8.schema=t8_fresh_s2_v1
if [[ ! -x "$VALIDATOR" ]]; then
  echo T8_STATUS=ERROR
  echo T8_CLASSIFICATION=missing_validator
  echo "T8_ERROR=missing expected executable validator: $VALIDATOR" >&2
  exit 2
fi

run_case() {
  local name="$1" erc="$2" estatus="$3" eclass="$4"
  local dir src out log cap
  dir="$CASES/$name"
  src="$dir/source fixture.cr"
  out="$dir/output fixture"
  log="$dir/validator.log"
  cap="$MAX_LOG_BYTES"
  mkdir -p "$dir"; printf '%s\n' 'puts 42' >"$src"
  case "$name" in
    output_cap|runner_log_overflow|runtime_log_overflow) cap=256 ;;
  esac
  if [[ "$name" == reused_output ]]; then mkdir -p "$out"; write_stub "$out/cv2_s2"; fi
  if [[ "$name" == nonempty_output ]]; then mkdir -p "$out"; printf '%s\n' stale >"$out/stale.txt"; fi
  if [[ "$name" == symlink_output ]]; then mkdir -p "$dir/real"; ln -s real "$out"; fi
  set +e
  T8_BOOTSTRAP_RUNNER="$ROOT_DIR/regression_tests/t8_fresh_s2_readiness_fake_runner.sh" \
  T8_CHAIN_RUNNER="$ROOT_DIR/regression_tests/t8_fresh_s2_readiness_fake_runner.sh" \
  T8_FAKE_CHAIN_CHILD=1 T8_FAKE_CASE="$name" T8_FAKE_SOURCE="$src" T8_FAKE_OUTPUT="$out" \
  T8_MAX_LOG_BYTES="$cap" T8_TIMEOUT_SEC=180 T8_MEM_MB=12288 \
  "$VALIDATOR" --source "$src" --out "$out" >"$log" 2>&1
  local rc="$?"; set -e
  local schema status_count class_count status class
  schema="$(grep -c '^t8.schema=t8_fresh_s2_v1$' "$log" || true)"
  status_count="$(grep -c '^T8_STATUS=' "$log" || true)"
  class_count="$(grep -c '^T8_CLASSIFICATION=' "$log" || true)"
  status="$(sed -n 's/^T8_STATUS=//p' "$log" | tail -1)"
  class="$(sed -n 's/^T8_CLASSIFICATION=//p' "$log" | tail -1)"
  if [[ "$rc" -ne "$erc" || "$schema" -ne 1 || "$status_count" -ne 1 ||
        "$class_count" -ne 1 || "$status" != "$estatus" || "$class" != "$eclass" ]]; then
    echo "T8_FAKE_CASE=$name expected_rc=$erc observed_rc=$rc status=${status:-missing} class=${class:-missing}" >&2
    sed -n '1,120p' "$log" >&2 || true
    return 1
  fi
  local receipt="$out.t8.receipt"
  [[ -f "$receipt" && ! -L "$receipt" ]] || {
    echo "T8_FAKE_CASE=$name missing receipt: $receipt" >&2
    return 1
  }
  local receipt_schema receipt_status receipt_class
  receipt_schema="$(grep -c '^t8.schema=t8_fresh_s2_v1$' "$receipt" || true)"
  receipt_status="$(grep -c '^T8_STATUS=' "$receipt" || true)"
  receipt_class="$(grep -c '^T8_CLASSIFICATION=' "$receipt" || true)"
  [[ "$receipt_schema" -eq 1 && "$receipt_status" -eq 1 && "$receipt_class" -eq 1 ]] || {
    echo "T8_FAKE_CASE=$name receipt cardinality mismatch" >&2
    return 1
  }
  [[ "$(sed -n 's/^T8_STATUS=//p' "$receipt")" == "$estatus" &&
     "$(sed -n 's/^T8_CLASSIFICATION=//p' "$receipt")" == "$eclass" ]] || {
    echo "T8_FAKE_CASE=$name receipt status mismatch" >&2
    return 1
  }
  local required_field required_count
  for required_field in t8.timeout_sec t8.mem_mb t8.cache_mode; do
    required_count="$(awk -F= -v key="$required_field" '$1 == key { n += 1; if ($2 == "") bad = 1 } END { print (n == 1 && !bad) ? 1 : 0 }' "$receipt")"
    [[ "$required_count" -eq 1 ]] || {
      echo "T8_FAKE_CASE=$name receipt field count mismatch: $required_field count=$required_count" >&2
      return 1
    }
  done
  if [[ "$name" == explicit_timeout ]]; then
    [[ "$(sed -n 's/^t8.timeout_sec=//p' "$receipt")" == 180 &&
       "$(sed -n 's/^t8.mem_mb=//p' "$receipt")" == 12288 &&
       "$(sed -n 's/^t8.cache_mode=//p' "$receipt")" == cold ]] || {
      echo "T8_FAKE_CASE=$name receipt execution parameters mismatch" >&2
      return 1
    }
  fi
  if [[ "$estatus" == GREEN ]]; then
    local field count
    [[ -f "$receipt" && ! -L "$receipt" ]] || {
      echo "T8_FAKE_CASE=$name missing receipt: $receipt" >&2
      return 1
    }
    for field in \
      t8.source_sha256_before t8.source_sha256_after \
      t8.source_tree_sha256_before t8.source_tree_sha256_after t8.git_head \
      t8.git_patch_sha256_before t8.git_patch_sha256_after \
      t8.runner_sha256_before t8.runner_sha256_after \
      t8.validator_sha256_before t8.validator_sha256_after \
      t8.cache_mode t8.output_fresh t8.stage1_sha256 t8.stage2_sha256 \
      t8.stage2_wall_ms t8.smoke_plain t8.smoke_noprelude t8.resource; do
      count="$(awk -F= -v key="$field" '$1 == key { n += 1; if ($2 == "") bad = 1 } END { print (n == 1 && !bad) ? 1 : 0 }' "$receipt")"
      if [[ "$count" -ne 1 ]] || ! grep -q "^${field}=" "$receipt"; then
        echo "T8_FAKE_CASE=$name receipt field count mismatch: $field count=$count" >&2
        sed -n '1,160p' "$receipt" >&2 || true
        return 1
      fi
    done
  fi
  echo "T8_FAKE_CASE=$name rc=$rc status=$status classification=$class"
}

run_case at_180 0 GREEN fresh_both_smoke
run_case over_180 1 MEASURED_RED over_budget
run_case missing_resource 1 RESOURCE_UNKNOWN resource_unknown
run_case malformed_resource 2 ERROR malformed_resource
run_case duplicate_resource 2 ERROR malformed_resource
run_case zero_resource 2 ERROR malformed_resource
run_case bogus_tree_mode 2 ERROR malformed_resource
run_case incomplete_tree 2 ERROR malformed_resource
run_case tree_sample_mismatch 2 ERROR malformed_resource
run_case partial_resource 1 RESOURCE_UNKNOWN resource_unknown
run_case explicit_timeout 1 MEASURED_RED stage2_timeout
run_case ambiguous_rc143 2 ERROR ambiguous_exit_143
run_case no_stage2 2 ERROR stage2_artifact_missing
run_case nested_s2_symlink 2 ERROR stage2_artifact_symlink
run_case plain_only 1 MEASURED_RED noprelude_smoke_unavailable
run_case no_prelude_only 1 MEASURED_RED plain_smoke_unavailable
run_case wrong_output 1 MEASURED_RED smoke_output_mismatch
run_case extra_output 1 MEASURED_RED smoke_output_mismatch
run_case stderr_output 1 MEASURED_RED smoke_output_mismatch
run_case forged_diagnostic 1 MEASURED_RED smoke_output_mismatch
run_case warm_cache 1 MEASURED_RED warm_cache_nonfresh
run_case cache_contradiction 2 ERROR cache_identity_mismatch
run_case source_mutation 2 ERROR source_hash_mismatch
run_case provenance_contradiction 2 ERROR provenance_mismatch
run_case reused_output 2 ERROR output_reused
run_case symlink_output 2 ERROR output_symlink
run_case nonempty_output 2 ERROR output_reused
run_case output_cap 2 ERROR output_cap_exceeded
run_case runner_log_overflow 2 ERROR output_cap_exceeded
run_case runtime_log_overflow 2 ERROR output_cap_exceeded
run_case stage2_log_symlink 2 ERROR output_symlink
run_case runtime_log_symlink 2 ERROR output_symlink
run_case dirty_source_valid 0 GREEN fresh_both_smoke

run_internal_error_tmpdir_probe() {
  local dir="$CASES/tmpdir_dev_null" src="$CASES/tmpdir_dev_null/source.cr" out="$CASES/tmpdir_dev_null/output" receipt="$CASES/tmpdir_dev_null/explicit.t8.receipt" log="$CASES/tmpdir_dev_null/validator.log"
  mkdir -p "$dir"; printf '%s\n' 'puts 42' >"$src"
  set +e
  TMPDIR=/dev/null T8_BOOTSTRAP_RUNNER="$ROOT_DIR/regression_tests/t8_fresh_s2_readiness_fake_runner.sh" \
  T8_CHAIN_RUNNER="$ROOT_DIR/regression_tests/t8_fresh_s2_readiness_fake_runner.sh" \
  T8_FAKE_CHAIN_CHILD=1 T8_FAKE_CASE=at_180 T8_FAKE_SOURCE="$src" T8_FAKE_OUTPUT="$out" \
  "$VALIDATOR" --source "$src" --out "$out" --receipt "$receipt" >"$log" 2>&1
  local rc="$?"; set -e
  [[ "$rc" -eq 2 ]] || { echo "T8_FAKE_CASE=tmpdir_dev_null rc=$rc" >&2; return 1; }
  [[ "$(grep -c '^t8.schema=t8_fresh_s2_v1$' "$log" || true)" -eq 1 &&
     "$(grep -c '^T8_STATUS=ERROR$' "$log" || true)" -eq 1 &&
     "$(grep -c '^T8_CLASSIFICATION=internal_error$' "$log" || true)" -eq 1 ]] || return 1
  [[ -f "$receipt" && ! -L "$receipt" ]] || return 1
  [[ "$(grep -c '^t8.schema=t8_fresh_s2_v1$' "$receipt" || true)" -eq 1 &&
     "$(grep -c '^T8_STATUS=ERROR$' "$receipt" || true)" -eq 1 &&
     "$(grep -c '^T8_CLASSIFICATION=internal_error$' "$receipt" || true)" -eq 1 ]] || return 1
  [[ ! -e "$out/cv2_s1" ]] || { echo 'tmpdir probe unexpectedly ran fake chain' >&2; return 1; }
  echo 'T8_FAKE_CASE=tmpdir_dev_null rc=2 status=ERROR classification=internal_error'
}

run_receipt_write_failure_probe() {
  local dir="$CASES/receipt_write_failure" src="$CASES/receipt_write_failure/source.cr" out="$CASES/receipt_write_failure/output" log="$CASES/receipt_write_failure/validator.log"
  mkdir -p "$dir"; printf '%s\n' 'puts 42' >"$src"
  set +e
  T8_BOOTSTRAP_RUNNER="$ROOT_DIR/regression_tests/t8_fresh_s2_readiness_fake_runner.sh" \
  T8_CHAIN_RUNNER="$ROOT_DIR/regression_tests/t8_fresh_s2_readiness_fake_runner.sh" \
  T8_FAKE_CHAIN_CHILD=1 T8_FAKE_CASE=at_180 T8_FAKE_SOURCE="$src" T8_FAKE_OUTPUT="$out" \
  T8_TIMEOUT_SEC=180 T8_MEM_MB=12288 \
  "$VALIDATOR" --source "$src" --out "$out" --receipt /dev/null/receipt >"$log" 2>&1
  local rc="$?"; set -e
  [[ "$rc" -eq 2 ]] || { echo "T8_FAKE_CASE=receipt_write_failure rc=$rc" >&2; return 1; }
  [[ "$(grep -c '^t8.schema=t8_fresh_s2_v1$' "$log" || true)" -eq 1 &&
     "$(grep -c '^T8_STATUS=ERROR$' "$log" || true)" -eq 1 &&
     "$(grep -c '^T8_CLASSIFICATION=receipt_write_failed$' "$log" || true)" -eq 1 ]] || {
    echo 'T8_FAKE_CASE=receipt_write_failure stdout cardinality mismatch' >&2
    return 1
  }
  [[ ! -e /dev/null/receipt ]] || { echo 'receipt unexpectedly exists below /dev/null' >&2; return 1; }
  echo 'T8_FAKE_CASE=receipt_write_failure rc=2 status=ERROR classification=receipt_write_failed'
}

run_hang_interrupt_probe() {
  local dir="$CASES/hang" src="$CASES/hang/source.cr" out="$CASES/hang/output" log="$CASES/hang/validator.log"
  mkdir -p "$dir"; printf '%s\n' 'puts 42' >"$src"
  set +e
  T8_BOOTSTRAP_RUNNER="$ROOT_DIR/regression_tests/t8_fresh_s2_readiness_fake_runner.sh" \
  T8_CHAIN_RUNNER="$ROOT_DIR/regression_tests/t8_fresh_s2_readiness_fake_runner.sh" \
  T8_FAKE_CHAIN_CHILD=1 T8_FAKE_CASE=hang T8_FAKE_SOURCE="$src" T8_FAKE_OUTPUT="$out" \
  "$VALIDATOR" --source "$src" --out "$out" >"$log" 2>&1 &
  # Capture the background PID from the shell instead of a process-table query.
  local pid=$!
  sleep 0.3
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid"; local rc="$?"
  set -e
  [[ "$rc" -eq 2 ]] || { echo "T8_FAKE_CASE=hang rc=$rc" >&2; return 1; }
  [[ "$(grep -c '^t8.schema=t8_fresh_s2_v1$' "$log" || true)" -eq 1 &&
     "$(grep -c '^T8_STATUS=ERROR$' "$log" || true)" -eq 1 &&
     "$(grep -c '^T8_CLASSIFICATION=interrupted$' "$log" || true)" -eq 1 ]] || return 1
  [[ -f "$out.t8.receipt" && ! -L "$out.t8.receipt" ]] || return 1
  if [[ -e "$out/fake.pid" ]]; then
    echo 'hang fake child marker survived TERM' >&2
    return 1
  fi
  echo 'T8_FAKE_CASE=hang rc=2 status=ERROR classification=interrupted'
}

run_internal_error_tmpdir_probe
run_receipt_write_failure_probe
run_hang_interrupt_probe
echo t8_fresh_s2_readiness_fake_matrix_ok
