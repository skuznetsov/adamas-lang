#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_external_sink_preflight.sh

Temp-source preflight for Slice 0k-DO.

It copies src/ to a temporary directory, injects an env-gated external
LLVMIRGenerator sink path into the temporary CLI only, builds a temporary
stage1 compiler from that copy, proves the host-stage tiny path is not dead,
then runs the generated-stage transaction report with the same env gate.

This is a falsifier for the default-mode function-emission sink boundary. It
does not edit tracked compiler source and does not admit external sinks as a
resource fix.

Environment:
  CRYSTAL_BIN            Crystal compiler used to build the temp stage1
                         (default: crystal).
  KEEP_TMP=1             Keep temporary artifacts and nested classifier dirs.
  STAGE2_BUILD_TIMEOUT   run_safe timeout for building generated s2
                         (default: 300).
  STAGE2_BUILD_MEM_MB    run_safe RSS cap for building generated s2
                         (default: 4096).
  SMOKE_TIMEOUT          run_safe timeout for produced-s2 compiles
                         (default: 120).
  SMOKE_MEM_MB           run_safe RSS cap for produced-s2 compiles
                         (default: 4096).
  TAIL_LINES             Failure/frontier tail lines for nested report
                         (default: 80).
  REQUIRE_REFUTED=1      Exit nonzero unless the current external-sink
                         empty-IR / missing-main refutation reproduces.

Classifications:
  external_sink_preflight_refuted_empty_ir
  external_sink_preflight_host_failed
  external_sink_preflight_generated_stage_drift

Rejected shortcuts:
  - enabling external sinks in production from this script alone;
  - raising memory limits;
  - forcing ADAMAS_LLVM_WORKERS=1;
  - patching worker/rand/tail/metadata/backend behavior.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-external-sink.XXXXXX")"
NESTED_TX_TMP=""
NESTED_CLASSIFIER_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    [[ -n "$NESTED_TX_TMP" ]] && echo "kept_report_tmp=$NESTED_TX_TMP"
    [[ -n "$NESTED_CLASSIFIER_TMP" ]] && echo "kept_classifier_tmp=$NESTED_CLASSIFIER_TMP"
  else
    [[ -n "$NESTED_TX_TMP" && "$NESTED_TX_TMP" == "$ROOT_DIR/tmp/generated-stage-execution-tx."* ]] && rm -rf "$NESTED_TX_TMP"
    [[ -n "$NESTED_CLASSIFIER_TMP" && "$NESTED_CLASSIFIER_TMP" == "$ROOT_DIR/tmp/generated-stage-llvm-entry."* ]] && rm -rf "$NESTED_CLASSIFIER_TMP"
    rm -rf "$TMP_DIR"
    rm -rf "$ROOT_DIR/tmp/llvm_cache"
  fi
}
trap cleanup EXIT

CRYSTAL_BIN="${CRYSTAL_BIN:-crystal}"
STAGE2_BUILD_TIMEOUT="${STAGE2_BUILD_TIMEOUT:-300}"
STAGE2_BUILD_MEM_MB="${STAGE2_BUILD_MEM_MB:-4096}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-120}"
SMOKE_MEM_MB="${SMOKE_MEM_MB:-4096}"
TAIL_LINES="${TAIL_LINES:-80}"

TMP_SRC="$TMP_DIR/src"
STAGE1="$TMP_DIR/adamas_external_sink_stage1"
S2="$TMP_DIR/adamas_external_sink_s2"
BUILD_LOG="$TMP_DIR/stage1_build.log"
S2_BUILD_LOG="$TMP_DIR/s2_build.log"
HOST_SRC="$TMP_DIR/host_puts42.cr"
HOST_BIN="$TMP_DIR/host_puts42"
HOST_COMPILE_LOG="$TMP_DIR/host_compile.log"
HOST_RUN_LOG="$TMP_DIR/host_run.log"
REPORT_LOG="$TMP_DIR/generated_stage_report.log"

echo "# Generated Stage External Sink Preflight"
echo "repo=$ROOT_DIR"
echo "crystal_bin=$CRYSTAL_BIN"
echo "stage1=$STAGE1"
echo "generated_s2=$S2"
echo "stage2_build_timeout=$STAGE2_BUILD_TIMEOUT"
echo "stage2_build_mem_mb=$STAGE2_BUILD_MEM_MB"
echo "smoke_timeout=$SMOKE_TIMEOUT"
echo "smoke_mem_mb=$SMOKE_MEM_MB"
echo "tail_lines=$TAIL_LINES"
echo "require_refuted=${REQUIRE_REFUTED:-0}"
echo "note: temp-source-copy preflight; tracked compiler source is not edited"

cp -R "$ROOT_DIR/src" "$TMP_SRC"

CLI_FILE="$TMP_SRC/compiler/cli.cr"
ruby - "$CLI_FILE" <<'RUBY'
path = ARGV.fetch(0)
src = File.read(path)

old = <<'CRYSTAL'
          llvm_ir = llvm_gen.generate
          if BootstrapEnv.enabled?("ADAMAS_TRACE_STDERR")
            LibC.write(2, "[STAGE2_TRACE] step5: generate done\n".to_unsafe, 36_u64)
          end

          # V2 BOOTSTRAP: keep file IO out of LLVMIRGenerator. Produced stage2
          # currently crashes when the backend returns through an external IO sink.
          LibC.unlink(ll_file.to_unsafe)
          fd = LibC.open(ll_file.to_unsafe, LibC::O_WRONLY | LibC::O_CREAT | LibC::O_TRUNC, 0o644)
          if fd < 0
            err_io.puts "Failed to open #{ll_file} for writing"
            return 1
          end

          begin
            llvm_ir_bytes = write_all_fd(fd, llvm_ir.to_slice)
          ensure
            LibC.close(fd)
          end
CRYSTAL

new = <<'CRYSTAL'
          if BootstrapEnv.enabled?("ADAMAS_LLVM_EXTERNAL_SINK_PROBE")
            File.open(ll_file, "w") do |llvm_io|
              llvm_gen.generate(llvm_io)
            end
            llvm_ir_bytes = if info = File.info?(ll_file)
                              info.size.to_i64
                            else
                              0_i64
                            end
            if BootstrapEnv.enabled?("ADAMAS_TRACE_STDERR")
              LibC.write(2, "[STAGE2_TRACE] step5: generate external sink done\n".to_unsafe, 51_u64)
            end
          else
            llvm_ir = llvm_gen.generate
            if BootstrapEnv.enabled?("ADAMAS_TRACE_STDERR")
              LibC.write(2, "[STAGE2_TRACE] step5: generate done\n".to_unsafe, 36_u64)
            end

            # V2 BOOTSTRAP: keep file IO out of LLVMIRGenerator. Produced stage2
            # currently crashes when the backend returns through an external IO sink.
            LibC.unlink(ll_file.to_unsafe)
            fd = LibC.open(ll_file.to_unsafe, LibC::O_WRONLY | LibC::O_CREAT | LibC::O_TRUNC, 0o644)
            if fd < 0
              err_io.puts "Failed to open #{ll_file} for writing"
              return 1
            end

            begin
              llvm_ir_bytes = write_all_fd(fd, llvm_ir.to_slice)
            ensure
              LibC.close(fd)
            end
          end
CRYSTAL

unless src.include?(old)
  abort "external-sink preflight injection anchor not found in #{path}"
end

File.write(path, src.sub(old, new))
RUBY

set +e
"$CRYSTAL_BIN" build "$TMP_SRC/adamas.cr" -o "$STAGE1" --error-trace >"$BUILD_LOG" 2>&1
build_rc=$?
set -e
echo "stage1_build_rc=$build_rc"
if [[ $build_rc -ne 0 || ! -x "$STAGE1" ]]; then
  echo "stage1_build_tail:"
  tail -120 "$BUILD_LOG" || true
  echo "classification=external_sink_preflight_host_failed"
  [[ "${REQUIRE_REFUTED:-0}" == "1" ]] && exit 9
  exit 0
fi

cat >"$HOST_SRC" <<'CR'
puts 42
CR

set +e
ADAMAS_LLVM_EXTERNAL_SINK_PROBE=1 "$STAGE1" "$HOST_SRC" -o "$HOST_BIN" >"$HOST_COMPILE_LOG" 2>&1
host_compile_rc=$?
host_run_rc=99
if [[ $host_compile_rc -eq 0 && -x "$HOST_BIN" ]]; then
  "$ROOT_DIR/scripts/run_safe.sh" "$HOST_BIN" 5 512 >"$HOST_RUN_LOG" 2>&1
  host_run_rc=$?
fi
set -e

host_stdout="$(awk '/^=== STDOUT ===/{flag=1; next} /^=== STDERR ===/{flag=0} flag { print }' "$HOST_RUN_LOG" 2>/dev/null | tr -d '\r' | tail -1 || true)"
host_ll="$HOST_BIN.ll"
host_ll_size=0
[[ -f "$host_ll" ]] && host_ll_size="$(wc -c <"$host_ll" | tr -d ' ')"

echo "host_compile_rc=$host_compile_rc"
echo "host_run_rc=$host_run_rc"
echo "host_stdout=${host_stdout:-missing}"
echo "host_ll_size=$host_ll_size"

if [[ $host_compile_rc -ne 0 || $host_run_rc -ne 0 || "$host_stdout" != "42" || "$host_ll_size" -le 0 ]]; then
  echo "host_compile_tail:"
  tail -120 "$HOST_COMPILE_LOG" || true
  echo "host_run_log:"
  cat "$HOST_RUN_LOG" 2>/dev/null || true
  echo "classification=external_sink_preflight_host_failed"
  [[ "${REQUIRE_REFUTED:-0}" == "1" ]] && exit 9
  exit 0
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$STAGE1" "$STAGE2_BUILD_TIMEOUT" "$STAGE2_BUILD_MEM_MB" \
  "$TMP_SRC/adamas.cr" -o "$S2" >"$S2_BUILD_LOG" 2>&1
s2_build_rc=$?
set -e
echo "s2_build_rc=$s2_build_rc"
if [[ $s2_build_rc -ne 0 || ! -x "$S2" ]]; then
  echo "s2_build_tail:"
  tail -160 "$S2_BUILD_LOG" || true
  echo "classification=external_sink_preflight_host_failed"
  [[ "${REQUIRE_REFUTED:-0}" == "1" ]] && exit 9
  exit 0
fi

set +e
KEEP_TMP=1 \
ADAMAS_LLVM_EXTERNAL_SINK_PROBE=1 \
STAGE1_COMPILER="$STAGE1" \
GENERATED_S2="$S2" \
STAGE2_BUILD_TIMEOUT="$STAGE2_BUILD_TIMEOUT" \
STAGE2_BUILD_MEM_MB="$STAGE2_BUILD_MEM_MB" \
SMOKE_TIMEOUT="$SMOKE_TIMEOUT" \
SMOKE_MEM_MB="$SMOKE_MEM_MB" \
TAIL_LINES="$TAIL_LINES" \
  "$ROOT_DIR/scripts/generated_stage_execution_transaction_report.sh" >"$REPORT_LOG" 2>&1
report_rc=$?
set -e

NESTED_TX_TMP="$(awk -F= '$1 == "kept_tmp" { print $2; exit }' "$REPORT_LOG" 2>/dev/null || true)"
NESTED_CLASSIFIER_TMP="$(awk -F= '$1 == "kept_classifier_tmp" { print $2; exit }' "$REPORT_LOG" 2>/dev/null || true)"

report_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, index($0, "=") + 1); found = 1; exit } END { if (!found) exit 1 }' "$REPORT_LOG" 2>/dev/null || true
}

default_boundary="$(report_value "resource.default_mode_boundary")"
workers1_boundary="$(report_value "resource.workers1_mode_boundary")"
join_status="$(report_value "join_status")"
default_llvm_rows="$(report_value "runtime.default_llvm_generate_phase_rows")"
default_memory_kill="$(report_value "resource.default_memory_kill")"
commit_record="$(report_value "output.commit_record")"
generated_s2="$(report_value "invocation.generated_s2")"

default_ll="$NESTED_CLASSIFIER_TMP/default_workers_out.ll"
default_log="$NESTED_CLASSIFIER_TMP/default_workers_compile.log"
default_ll_size="missing"
missing_main=0
[[ -f "$default_ll" ]] && default_ll_size="$(wc -c <"$default_ll" | tr -d ' ')"
if [[ -f "$default_log" ]] && grep -Fq '"_main"' "$default_log"; then
  missing_main=1
fi

echo "report_rc=$report_rc"
echo "generated_s2=${generated_s2:-missing}"
echo "report.default_mode_boundary=${default_boundary:-missing}"
echo "report.workers1_mode_boundary=${workers1_boundary:-missing}"
echo "report.join_status=${join_status:-missing}"
echo "report.default_llvm_generate_phase_rows=${default_llvm_rows:-missing}"
echo "report.default_memory_kill=${default_memory_kill:-missing}"
echo "report.output_commit_record=${commit_record:-missing}"
echo "default_workers_ll_size=$default_ll_size"
echo "default_workers_missing_main=$missing_main"

classification="external_sink_preflight_generated_stage_drift"
if [[ "$default_boundary" == "after_output_start_before_llvm_generate" &&
      "$join_status" == "phase_local_only" &&
      "${default_llvm_rows:-missing}" == "0" &&
      "${default_memory_kill:-missing}" == "0" &&
      "$commit_record" == "binary_compile_rc:1" &&
      "$default_ll_size" == "0" &&
      "$missing_main" == "1" ]]; then
  classification="external_sink_preflight_refuted_empty_ir"
fi

echo "classification=$classification"
echo "report_log=$REPORT_LOG"
echo "default_workers_log=$default_log"

if [[ "$classification" != "external_sink_preflight_refuted_empty_ir" || "${TAIL_ALWAYS:-0}" == "1" ]]; then
  echo "report_tail:"
  tail -160 "$REPORT_LOG" || true
  if [[ -f "$default_log" ]]; then
    echo "default_workers_tail:"
    tail -160 "$default_log" || true
  fi
fi

if [[ "${REQUIRE_REFUTED:-0}" == "1" && "$classification" != "external_sink_preflight_refuted_empty_ir" ]]; then
  exit 9
fi
