#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/mir_timed_phase_hir_producer_order_classifier.sh

Read-only classifier for the post-0k-CN HIR producer ordering seam.

It copies src/ to a temporary directory, injects default-off probes into the
temporary copy of ast_to_hir.cr, builds a temporary probe compiler, and checks
whether CopyPropagationPass#timed_cp_phase(String, &) is first lowered as a
shared Void-yield wrapper before the apply_collect_affected_blocks callsite
records its Set(UInt32) block return.

Environment:
  CRYSTAL_BIN             Crystal compiler used to build the temp probe (default: crystal).
  RUN_CURRENT_CN=1        Also run the 0k-CN source-seam classifier first.
  KEEP_TMP=1              Keep temporary artifacts and print their paths.
  REQUIRE_CURRENT_CO=1    Exit nonzero unless the current 0k-CO seam reproduces.

Current accepted measured-red classification:
  current_0k_co_hir_timed_phase_shared_wrapper_order_frontier

This script is a classifier only. It does not edit tracked compiler source and
is not permission to patch timed_cp_phase, CopyPropagation, HIR/MIR/LLVM
block-return handling, Set/Hash delegates, workers, output, or BlockOwner.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/mir-timed-hir-producer-order.XXXXXX")"

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
    rm -rf "$ROOT_DIR/tmp/llvm_cache"
  fi
}
trap cleanup EXIT

CRYSTAL_BIN="${CRYSTAL_BIN:-crystal}"
TMP_SRC="$TMP_DIR/src"
PROBE_BIN="$TMP_DIR/adamas_tprod_probe"
CN_LOG="$TMP_DIR/cn_classifier.log"
BUILD_LOG="$TMP_DIR/build.log"
RUN_LOG="$TMP_DIR/run.log"
HIR_BASE="$TMP_DIR/tprod_hir"

echo "# MIR Timed Phase HIR Producer Order Classifier"
echo "repo=$ROOT_DIR"
echo "crystal_bin=$CRYSTAL_BIN"
echo "run_current_cn=${RUN_CURRENT_CN:-0}"
echo "require_current_co=${REQUIRE_CURRENT_CO:-0}"
echo "note: temp-source-copy probe; tracked compiler source is not edited"

cn_classification="skipped"
if [[ "${RUN_CURRENT_CN:-0}" == "1" ]]; then
  set +e
  REQUIRE_CURRENT_CN=1 "$ROOT_DIR/scripts/mir_timed_phase_source_seam_classifier.sh" >"$CN_LOG" 2>&1
  cn_rc=$?
  set -e
  echo "cn_classifier_rc=$cn_rc"
  if [[ $cn_rc -ne 0 ]]; then
    echo "classification=cn_classifier_failed"
    echo "cn_classifier_tail:"
    tail -120 "$CN_LOG" || true
    exit 20
  fi
  cn_classification="$(awk -F= '$1 == "classification" { print $2; exit }' "$CN_LOG")"
fi
echo "cn_classification=$cn_classification"

cp -R "$ROOT_DIR/src" "$TMP_SRC"

AST_FILE="$TMP_SRC/compiler/hir/ast_to_hir.cr"
ruby - "$AST_FILE" <<'RUBY'
path = ARGV.fetch(0)
src = File.read(path)

replacements = [
  [
    "      block_return_name = stable_name\n\n      if type_param_name = block_return_type_param_name(mangled_method_name, base_method_name)\n",
    "      block_return_name = stable_name\n" \
    "      if env_get(\"ADAMAS_TIMED_PRODUCER_PROBE\") &&\n" \
    "         (mangled_method_name.includes?(\"CopyPropagationPass#timed_cp_phase\") ||\n" \
    "          base_method_name.includes?(\"CopyPropagationPass#timed_cp_phase\"))\n" \
    "        type_param_probe = block_return_type_param_name(mangled_method_name, base_method_name)\n" \
    "        STDERR.puts \"[TPROD_RECORD] mangled=\#{mangled_method_name} base=\#{base_method_name} block_return=\#{block_return_name} type_param=\#{type_param_probe || \"nil\"}\"\n" \
    "      end\n\n" \
    "      if type_param_name = block_return_type_param_name(mangled_method_name, base_method_name)\n",
  ],
  [
    "      if candidate == TypeRef::VOID || candidate == TypeRef::NIL\n        nil\n      else\n        candidate\n      end\n",
    "      if candidate == TypeRef::VOID || candidate == TypeRef::NIL\n" \
    "        if env_get(\"ADAMAS_TIMED_PRODUCER_PROBE\") && ctx.function.name.includes?(\"CopyPropagationPass#timed_cp_phase\")\n" \
    "          STDERR.puts \"[TPROD_FALLBACK] ctx=\#{ctx.function.name} base=\#{base_name} lookup=\#{lookup_names.join(\"|\")} block_ret=\#{block_ret_name || \"nil\"} block_src=\#{block_ret_src || \"nil\"} candidate=\#{get_type_name_from_ref(candidate)} result=nil\"\n" \
    "        end\n" \
    "        nil\n" \
    "      else\n" \
    "        if env_get(\"ADAMAS_TIMED_PRODUCER_PROBE\") && ctx.function.name.includes?(\"CopyPropagationPass#timed_cp_phase\")\n" \
    "          STDERR.puts \"[TPROD_FALLBACK] ctx=\#{ctx.function.name} base=\#{base_name} lookup=\#{lookup_names.join(\"|\")} block_ret=\#{block_ret_name || \"nil\"} block_src=\#{block_ret_src || \"nil\"} candidate=\#{get_type_name_from_ref(candidate)} result=\#{get_type_name_from_ref(candidate)}\"\n" \
    "        end\n" \
    "        candidate\n" \
    "      end\n",
  ],
  [
    "      if block_return_name.nil? && block_for_inline\n        block_return_name = inline_block_return_type_name(block_for_inline, block_param_types_inline, @current_class)\n      end\n      if block_return_name\n",
    "      if block_return_name.nil? && block_for_inline\n" \
    "        block_return_name = inline_block_return_type_name(block_for_inline, block_param_types_inline, @current_class)\n" \
    "      end\n" \
    "      if env_get(\"ADAMAS_TIMED_PRODUCER_PROBE\") &&\n" \
    "         (mangled_method_name.includes?(\"CopyPropagationPass#timed_cp_phase\") ||\n" \
    "          base_method_name.includes?(\"CopyPropagationPass#timed_cp_phase\"))\n" \
    "        STDERR.puts \"[TPROD_BLOCKRET] stage=before_record mangled=\#{mangled_method_name} base=\#{base_method_name} block_return=\#{block_return_name || \"nil\"} block_id=\#{block_id ? block_id.to_s : \"nil\"} block_for_inline=\#{block_for_inline ? 1 : 0}\"\n" \
    "      end\n" \
    "      if block_return_name\n",
  ],
  [
    "        if callsite_arg_types.any? { |t| t != TypeRef::VOID }\n          remember_callsite_arg_types(mangled_method_name, callsite_arg_types, callsite_arg_literals, callsite_arg_enum_names, has_block_call, has_named_args, call_named_arg_names)\n        end\n        record_block_return_type_for_call(mangled_method_name, base_method_name, block_return_name)\n",
    "        if callsite_arg_types.any? { |t| t != TypeRef::VOID }\n" \
    "          remember_callsite_arg_types(mangled_method_name, callsite_arg_types, callsite_arg_literals, callsite_arg_enum_names, has_block_call, has_named_args, call_named_arg_names)\n" \
    "        end\n" \
    "        if env_get(\"ADAMAS_TIMED_PRODUCER_PROBE\") &&\n" \
    "           (mangled_method_name.includes?(\"CopyPropagationPass#timed_cp_phase\") ||\n" \
    "            base_method_name.includes?(\"CopyPropagationPass#timed_cp_phase\"))\n" \
    "          STDERR.puts \"[TPROD_BLOCKRET] stage=after_target mangled=\#{mangled_method_name} base=\#{base_method_name} block_return=\#{block_return_name} block_target_arg_count=\#{block_target_arg_types.size}\"\n" \
    "        end\n" \
    "        record_block_return_type_for_call(mangled_method_name, base_method_name, block_return_name)\n",
  ],
  [
    "        if yield_return_function_for_block_call?(mangled_method_name, base_method_name, call_args.size, arg_types, receiver_base_for_return)\n          inferred = type_ref_for_name(block_return_name)\n          return_type = inferred if inferred != TypeRef::VOID\n        end\n",
    "        yield_return_for_block_call = yield_return_function_for_block_call?(mangled_method_name, base_method_name, call_args.size, arg_types, receiver_base_for_return)\n" \
    "        if env_get(\"ADAMAS_TIMED_PRODUCER_PROBE\") &&\n" \
    "           (mangled_method_name.includes?(\"CopyPropagationPass#timed_cp_phase\") ||\n" \
    "            base_method_name.includes?(\"CopyPropagationPass#timed_cp_phase\"))\n" \
    "          STDERR.puts \"[TPROD_YIELDRET_CALL] mangled=\#{mangled_method_name} base=\#{base_method_name} block_return=\#{block_return_name} result=\#{yield_return_for_block_call ? 1 : 0}\"\n" \
    "        end\n" \
    "        if yield_return_for_block_call\n" \
    "          inferred = type_ref_for_name(block_return_name)\n" \
    "          return_type = inferred if inferred != TypeRef::VOID\n" \
    "        end\n",
  ],
]

replacements.each do |before, after|
  unless src.include?(before)
    warn "missing instrumentation anchor"
    exit 2
  end
  src = src.sub(before, after)
end

File.write(path, src)
RUBY

set +e
"$CRYSTAL_BIN" build "$TMP_SRC/adamas.cr" -o "$PROBE_BIN" --error-trace >"$BUILD_LOG" 2>&1
build_rc=$?
set -e
echo "probe_build_rc=$build_rc"
if [[ $build_rc -ne 0 ]]; then
  echo "classification=probe_build_failed"
  tail -120 "$BUILD_LOG" || true
  exit 21
fi

set +e
ADAMAS_TIMED_PRODUCER_PROBE=1 ADAMAS_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$PROBE_BIN" 300 4096 \
  "$ROOT_DIR/src/adamas.cr" --emit hir --no-link -o "$HIR_BASE" >"$RUN_LOG" 2>&1
run_rc=$?
set -e
echo "probe_run_rc=$run_rc"
if [[ $run_rc -ne 0 ]]; then
  echo "classification=probe_run_failed"
  tail -120 "$RUN_LOG" || true
  exit 22
fi

first_fallback_nil_line="$(awk '/\[TPROD_FALLBACK\].*block_ret=nil.*candidate=Void.*result=nil/ { print NR; exit }' "$RUN_LOG")"
first_set_before_record_line="$(awk '/\[TPROD_BLOCKRET\].*stage=before_record.*block_return=Set\(UInt32\)/ { print NR; exit }' "$RUN_LOG")"
first_set_record_line="$(awk '/\[TPROD_RECORD\].*block_return=Set\(UInt32\)/ { print NR; exit }' "$RUN_LOG")"
first_set_yieldret_zero_line="$(awk '/\[TPROD_YIELDRET_CALL\].*block_return=Set\(UInt32\).*result=0/ { print NR; exit }' "$RUN_LOG")"

early_void_before_set=0
if [[ -n "$first_fallback_nil_line" && -n "$first_set_record_line" &&
      "$first_fallback_nil_line" -lt "$first_set_record_line" ]]; then
  early_void_before_set=1
fi

set_recorded_later=0
[[ -n "$first_set_record_line" ]] && set_recorded_later=1

set_yield_return_not_classified=0
[[ -n "$first_set_yieldret_zero_line" ]] && set_yield_return_not_classified=1

classification="timed_phase_hir_producer_order_unmatched"
if [[ $early_void_before_set -eq 1 &&
      $set_recorded_later -eq 1 &&
      $set_yield_return_not_classified -eq 1 ]]; then
  classification="current_0k_co_hir_timed_phase_shared_wrapper_order_frontier"
fi

echo "first_fallback_nil_line=${first_fallback_nil_line:-missing}"
echo "first_set_before_record_line=${first_set_before_record_line:-missing}"
echo "first_set_record_line=${first_set_record_line:-missing}"
echo "first_set_yieldret_zero_line=${first_set_yieldret_zero_line:-missing}"
echo "early_void_before_set=$early_void_before_set"
echo "set_recorded_later=$set_recorded_later"
echo "set_yield_return_not_classified=$set_yield_return_not_classified"
echo "classification=$classification"

echo "producer_trace_excerpt:"
rg -n "\\[TPROD_(FALLBACK|BLOCKRET|RECORD|YIELDRET_CALL)\\]" "$RUN_LOG" | sed -n '1,80p'

if [[ "${REQUIRE_CURRENT_CO:-0}" == "1" &&
      "$classification" != "current_0k_co_hir_timed_phase_shared_wrapper_order_frontier" ]]; then
  exit 23
fi

exit 0
