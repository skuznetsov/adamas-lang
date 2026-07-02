#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_lower_method_terminal_classifier.sh [source.cr]

Temp-source classifier for Slices 0k-DD/0k-DE.

It copies src/ to a temporary directory, injects default-off [MAT_METHOD_EXIT]
probes into the temporary ast_to_hir.cr, builds a temporary probe compiler, and
uses that probe as GENERATED_S2 for the existing created-body completion
classifier. Tracked compiler source is not edited.

Environment:
  STAGE1_COMPILER      Use an existing stage1 compiler instead of building one.
  STAGE2_BUILD_TIMEOUT run_safe timeout for building the generated probe (default: 600).
  STAGE2_BUILD_MEM_MB  run_safe RSS cap for building the generated probe (default: 4096).
  KEEP_TMP=1           Keep temporary artifacts and nested classifier dirs.
  MAX_CLASS_ROWS=N     Root-sized row threshold (default: 3).
  SAMPLES=N            Sample rows per section (default: 8).
  REQUIRE_REACHED=1    Exit nonzero unless the nested classifier reaches [MAT_EMIT].
  REQUIRE_ROOT_SIZED=1 Exit nonzero unless exactly one root-sized terminal class is selected.

This is a read-only classifier. It does not add backend rescue, forwarders,
requested-name forcing, per-method patches, NamedTuple/Tuple normalization,
ambient-map policy changes, lower_method signature changes, or BlockOwner
changes.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/lower-method-terminal.XXXXXX")"

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

MAX_CLASS_ROWS="${MAX_CLASS_ROWS:-3}"
SAMPLES="${SAMPLES:-8}"
TMP_SRC="$TMP_DIR/src"
PROBE_BIN="$TMP_DIR/adamas_lower_method_terminal_probe"
STAGE1="${STAGE1_COMPILER:-$TMP_DIR/adamas_stage1}"
STAGE1_BUILD_LOG="$TMP_DIR/stage1_build.log"
PROBE_BUILD_LOG="$TMP_DIR/probe_build.log"
CLASSIFIER_OUT="$TMP_DIR/completion_classifier.out"
SUMMARY_LOG="$TMP_DIR/terminal_summary.out"
STAGE2_BUILD_TIMEOUT="${STAGE2_BUILD_TIMEOUT:-600}"
STAGE2_BUILD_MEM_MB="${STAGE2_BUILD_MEM_MB:-4096}"

echo "# Generated Stage LowerMethod Terminal Classifier"
echo "repo=$ROOT_DIR"
echo "stage1=$STAGE1"
echo "stage2_build_timeout=$STAGE2_BUILD_TIMEOUT"
echo "stage2_build_mem_mb=$STAGE2_BUILD_MEM_MB"
echo "max_class_rows=$MAX_CLASS_ROWS"
echo "samples=$SAMPLES"
echo "require_reached=${REQUIRE_REACHED:-0}"
echo "require_root_sized=${REQUIRE_ROOT_SIZED:-0}"
echo "note: temp-source-copy classifier; tracked compiler source is not edited"

cp -R "$ROOT_DIR/src" "$TMP_SRC"

AST_FILE="$TMP_SRC/compiler/hir/ast_to_hir.cr"
ruby - "$AST_FILE" <<'RUBY'
path = ARGV.fetch(0)
src = File.read(path)

helper_anchor = "    # Lower a method within a class\n"
helper = <<'CRYSTAL'
    private def lower_method_terminal_probe(
      reason : String,
      class_name : String,
      method_name : String,
      full_name : String,
      override_name : String,
    ) : Nil
      return unless env_has?("ADAMAS_LOWER_METHOD_TERMINAL_PROBE")

      STDERR.puts "[MAT_METHOD_EXIT] reason=#{ledger_token(reason)} class=#{ledger_token(class_name)} method=#{ledger_token(method_name)} full=#{ledger_token(full_name)} override=#{ledger_token(override_name)}"
    end

    private def lower_method_entry_probe(
      class_name : String,
      method_name : String,
      override_name : String,
      call_arg_types : Array(TypeRef)?,
      node : Adamas::Compiler::Frontend::DefNode,
    ) : Nil
      return unless env_has?("ADAMAS_LOWER_METHOD_TERMINAL_PROBE")

      arg_ids = if types = call_arg_types
                  types.map { |type_ref| type_ref.id.to_s }.join(",")
                else
                  "nil"
                end
      source_path = source_path_for(@arena) || ""
      STDERR.puts "[MAT_METHOD_ENTRY] class=#{ledger_token(class_name)} method=#{ledger_token(method_name)} override=#{ledger_token(override_name)} call_arg_ids=#{ledger_token(arg_ids)} source=#{ledger_token(source_path)} line=#{node.span.start_line} col=#{node.span.start_column}"
    end

    private def lower_method_name_probe(
      class_name : String,
      method_name : String,
      base_name : String,
      candidate_full_name : String,
      full_name : String,
      override_name : String,
      param_types : Array(TypeRef),
    ) : Nil
      return unless env_has?("ADAMAS_LOWER_METHOD_TERMINAL_PROBE")

      param_ids = param_types.map { |type_ref| type_ref.id.to_s }.join(",")
      STDERR.puts "[MAT_METHOD_NAME] class=#{ledger_token(class_name)} method=#{ledger_token(method_name)} base=#{ledger_token(base_name)} candidate=#{ledger_token(candidate_full_name)} full=#{ledger_token(full_name)} override=#{ledger_token(override_name)} param_ids=#{ledger_token(param_ids)}"
    end

    private def lower_method_call_probe(
      path : String,
      requested_name : String,
      target_name : String,
      body_symbol : String,
      owner : String,
      method_name : String,
      override_name : String,
      call_arg_types : Array(TypeRef)?,
      node : Adamas::Compiler::Frontend::DefNode,
    ) : Nil
      return unless env_has?("ADAMAS_LOWER_METHOD_TERMINAL_PROBE")

      arg_ids = if types = call_arg_types
                  types.map { |type_ref| type_ref.id.to_s }.join(",")
                else
                  "nil"
                end
      def_name = safe_slice_to_string(node.name) || ""
      source_path = source_path_for(@arena) || ""
      STDERR.puts "[MAT_METHOD_CALL] path=#{ledger_token(path)} requested=#{ledger_token(requested_name)} target=#{ledger_token(target_name)} body=#{ledger_token(body_symbol)} owner=#{ledger_token(owner)} method=#{ledger_token(method_name)} override=#{ledger_token(override_name)} def=#{ledger_token(def_name)} call_arg_ids=#{ledger_token(arg_ids)} source=#{ledger_token(source_path)} line=#{node.span.start_line} col=#{node.span.start_column}"
    end

    private def lower_method_precall_probe(
      stage : String,
      requested_name : String,
      target_name : String,
      body_symbol : String,
      owner : String,
      override_name : String,
      call_arg_types : Array(TypeRef)?,
      func_def : Adamas::Compiler::Frontend::DefNode,
    ) : Nil
      return unless env_has?("ADAMAS_LOWER_METHOD_TERMINAL_PROBE")

      arg_ids = if types = call_arg_types
                  types.map { |type_ref| type_ref.id.to_s }.join(",")
                else
                  "nil"
                end
      def_name = safe_slice_to_string(func_def.name) || ""
      STDERR.puts "[MAT_PRECALL] stage=#{ledger_token(stage)} requested=#{ledger_token(requested_name)} target=#{ledger_token(target_name)} body=#{ledger_token(body_symbol)} owner=#{ledger_token(owner)} override=#{ledger_token(override_name)} def=#{ledger_token(def_name)} call_arg_ids=#{ledger_token(arg_ids)}"
    end

CRYSTAL

unless src.include?(helper_anchor)
  warn "missing lower_method helper anchor"
  exit 2
end
src = src.sub(helper_anchor, helper + helper_anchor)

replacements = [
  [
    "      method_name = forced_method_name.empty? ? (safe_slice_to_string(node.name) || \"\") : forced_method_name\n      effective_full_name_override = forced_full_name.empty? ? (full_name_override || \"\") : forced_full_name\n      is_initialize_method = method_name == \"initialize\"\n",
    "      method_name = forced_method_name.empty? ? (safe_slice_to_string(node.name) || \"\") : forced_method_name\n" \
    "      effective_full_name_override = forced_full_name.empty? ? (full_name_override || \"\") : forced_full_name\n" \
    "      is_initialize_method = method_name == \"initialize\"\n" \
    "      lower_method_entry_probe(class_name, method_name, effective_full_name_override, call_arg_types, node)\n",
  ],
  [
    "      if node.is_abstract\n        clear_pending_effect_annotations\n        return\n      end\n",
    "      if node.is_abstract\n" \
    "        clear_pending_effect_annotations\n" \
    "        lower_method_terminal_probe(\"abstract_method\", class_name, method_name, base_name, effective_full_name_override)\n" \
    "        return\n" \
    "      end\n",
  ],
  [
    "        clear_pending_effect_annotations\n        return\n      end\n\n      # Skip pointer primitives with no body",
    "        clear_pending_effect_annotations\n" \
    "        lower_method_terminal_probe(\"primitive_method\", class_name, method_name, base_name, effective_full_name_override)\n" \
    "        return\n" \
    "      end\n\n" \
    "      # Skip pointer primitives with no body",
  ],
  [
    "      if class_name.starts_with?(\"Pointer(\") || class_name.starts_with?(\"Pointer_\")\n        return if node.body.nil?\n      end\n",
    "      if class_name.starts_with?(\"Pointer(\") || class_name.starts_with?(\"Pointer_\")\n" \
    "        if node.body.nil?\n" \
    "          lower_method_terminal_probe(\"pointer_primitive_no_body\", class_name, method_name, base_name, effective_full_name_override)\n" \
    "          return\n" \
    "        end\n" \
    "      end\n",
  ],
  [
    "          register_pending_method_effects(base_name, 0)\n          return\n        end\n",
    "          register_pending_method_effects(base_name, 0)\n" \
    "          lower_method_terminal_probe(\"defer_untyped_params\", class_name, method_name, base_name, effective_full_name_override)\n" \
    "          return\n" \
    "        end\n",
  ],
  [
    %q{          debug_hook("method.lower.defer", "class=#{class_name} method=#{method_name} reason=partial_untyped_params") if DebugHooks::ENABLED
          register_pending_method_effects(base_name, 0)
          return
        end
},
    %q{          debug_hook("method.lower.defer", "class=#{class_name} method=#{method_name} reason=partial_untyped_params") if DebugHooks::ENABLED
} \
    "          register_pending_method_effects(base_name, 0)\n" \
    "          lower_method_terminal_probe(\"defer_partial_untyped_params\", class_name, method_name, base_name, effective_full_name_override)\n" \
    "          return\n" \
    "        end\n",
  ],
  [
    "      return unless v2_string_readable?(full_name)\n      return if full_name.empty?\n",
    "      unless v2_string_readable?(full_name)\n" \
    "        lower_method_terminal_probe(\"unreadable_full_name\", class_name, method_name, full_name, effective_full_name_override)\n" \
    "        return\n" \
    "      end\n" \
    "      if full_name.empty?\n" \
    "        lower_method_terminal_probe(\"empty_full_name\", class_name, method_name, full_name, effective_full_name_override)\n" \
    "        return\n" \
    "      end\n",
  ],
  [
    "      if full_name.empty?\n" \
    "        lower_method_terminal_probe(\"empty_full_name\", class_name, method_name, full_name, effective_full_name_override)\n" \
    "        return\n" \
    "      end\n\n" \
    "      register_pending_method_effects(full_name, param_types.size)\n",
    "      if full_name.empty?\n" \
    "        lower_method_terminal_probe(\"empty_full_name\", class_name, method_name, full_name, effective_full_name_override)\n" \
    "        return\n" \
    "      end\n\n" \
    "      lower_method_name_probe(class_name, method_name, base_name, candidate_full_name, full_name, effective_full_name_override, param_types)\n" \
    "      register_pending_method_effects(full_name, param_types.size)\n",
  ],
  [
    "        @current_method_is_class = old_method_is_class\n        return\n      end\n\n      func = @module.create_function(full_name, return_type)\n",
    "        @current_method_is_class = old_method_is_class\n" \
    "        lower_method_terminal_probe(\"already_has_body\", class_name, method_name, full_name, effective_full_name_override)\n" \
    "        return\n" \
    "      end\n\n" \
    "      func = @module.create_function(full_name, return_type)\n" \
    "      lower_method_terminal_probe(\"created_hir_function\", class_name, method_name, full_name, effective_full_name_override)\n",
  ],
  [
    "      @function_lowering_states[full_name] = FunctionLoweringState::Completed\n\n      # Restore previous method context\n",
    "      @function_lowering_states[full_name] = FunctionLoweringState::Completed\n" \
    "      lower_method_terminal_probe(\"completed_method\", class_name, method_name, full_name, effective_full_name_override)\n\n" \
    "      # Restore previous method context\n",
  ],
  [
    "                lower_method(owner, class_info, resolved_func_def, call_arg_types, call_arg_literals, call_arg_enum_names, override, force_class_method: force_class_method)\n",
    "                lower_method_call_probe(\"instance_class_info_lower_method\", instance_transaction.requested_name, instance_transaction.target_name, instance_transaction.body_symbol, owner, resolved_parts.method || \"\", override, call_arg_types, resolved_func_def)\n" \
    "                lower_method(owner, class_info, resolved_func_def, call_arg_types, call_arg_literals, call_arg_enum_names, override, force_class_method: force_class_method)\n",
  ],
  [
    "              if materialization_transaction_ledger_enabled?\n                log_call_materialization_transaction_ledger(instance_transaction)\n              end\n              old_type_param_map = @type_param_map\n",
    "              if materialization_transaction_ledger_enabled?\n" \
    "                log_call_materialization_transaction_ledger(instance_transaction)\n" \
    "              end\n" \
    "              lower_method_precall_probe(\"after_tx\", instance_transaction.requested_name, instance_transaction.target_name, instance_transaction.body_symbol, owner, override, call_arg_types, resolved_func_def)\n" \
    "              old_type_param_map = @type_param_map\n",
  ],
  [
    "              @current_namespace_override = namespace_override\n              begin\n",
    "              lower_method_precall_probe(\"inside_type_params\", instance_transaction.requested_name, instance_transaction.target_name, instance_transaction.body_symbol, owner, override, call_arg_types, resolved_func_def)\n" \
    "              @current_namespace_override = namespace_override\n" \
    "              lower_method_precall_probe(\"inside_namespace\", instance_transaction.requested_name, instance_transaction.target_name, instance_transaction.body_symbol, owner, override, call_arg_types, resolved_func_def)\n" \
    "              begin\n",
  ],
  [
    "                if call_arg_types && call_arg_types.size > 0\n                  actual_arity = count_non_block_params(resolved_func_def)\n",
    "                lower_method_precall_probe(\"before_arity\", instance_transaction.requested_name, instance_transaction.target_name, instance_transaction.body_symbol, owner, override, call_arg_types, resolved_func_def)\n" \
    "                if call_arg_types && call_arg_types.size > 0\n" \
    "                  actual_arity = count_non_block_params(resolved_func_def)\n",
  ],
  [
    "                if env_get(\"DEBUG_ENTRY_MATCHES\") && name.includes?(\"entry_matches\")\n",
    "                lower_method_precall_probe(\"after_arity\", instance_transaction.requested_name, instance_transaction.target_name, instance_transaction.body_symbol, owner, override, call_arg_types, resolved_func_def)\n" \
    "                if env_get(\"DEBUG_ENTRY_MATCHES\") && name.includes?(\"entry_matches\")\n",
  ],
]

replacements.each do |before, after|
  unless src.include?(before)
    warn "missing instrumentation anchor"
    warn before
    exit 3
  end
  src = src.sub(before, after)
end

File.write(path, src)
RUBY

if [[ -z "${STAGE1_COMPILER:-}" ]]; then
  set +e
  "$ROOT_DIR/scripts/build_stage1_original_cached.sh" debug "$STAGE1" --error-trace >"$STAGE1_BUILD_LOG" 2>&1
  stage1_rc=$?
  set -e
else
  stage1_rc=0
fi

echo "stage1_build_rc=$stage1_rc"
if [[ $stage1_rc -ne 0 || ! -x "$STAGE1" ]]; then
  echo "classification=stage1_build_failed"
  tail -120 "$STAGE1_BUILD_LOG" || true
  exit 20
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$STAGE1" "$STAGE2_BUILD_TIMEOUT" "$STAGE2_BUILD_MEM_MB" \
  "$TMP_SRC/adamas.cr" -o "$PROBE_BIN" >"$PROBE_BUILD_LOG" 2>&1
probe_build_rc=$?
set -e

echo "probe_build_rc=$probe_build_rc"
if [[ $probe_build_rc -ne 0 || ! -x "$PROBE_BIN" ]]; then
  echo "classification=probe_build_failed"
  tail -160 "$PROBE_BUILD_LOG" || true
  exit 21
fi

set +e
ADAMAS_LOWER_METHOD_TERMINAL_PROBE=1 \
  GENERATED_S2="$PROBE_BIN" \
  MAX_CLASS_ROWS="$MAX_CLASS_ROWS" \
  SAMPLES="$SAMPLES" \
  KEEP_TMP=1 \
  "$ROOT_DIR/scripts/generated_stage_created_body_visibility_classifier.sh" "$@" >"$CLASSIFIER_OUT" 2>&1
classifier_rc=$?
set -e

log_file="$(awk -F= '$1 == "log_file" { print $2; exit }' "$CLASSIFIER_OUT")"
classifier_classification="$(awk -F= '$1 == "classifier_classification" { print $2; exit }' "$CLASSIFIER_OUT")"
kept_classifier_tmp="$(awk -F= '$1 == "kept_classifier_tmp" { print $2; exit }' "$CLASSIFIER_OUT")"
nested_tmp="$(awk -F= '$1 == "kept_tmp" { print $2; exit }' "$CLASSIFIER_OUT" | tail -1)"

if [[ -z "$log_file" || ! -f "$log_file" ]]; then
  echo "classification=classifier_log_missing"
  echo "completion_classifier_rc=$classifier_rc"
  tail -160 "$CLASSIFIER_OUT" || true
  exit 22
fi

echo "completion_classifier_rc=$classifier_rc"
echo "completion_classifier_classification=$classifier_classification"
echo "completion_classifier_log=$log_file"

awk -v max_class_rows="$MAX_CLASS_ROWS" -v samples="$SAMPLES" '
  function field(name,    i, p) {
    for (i = 1; i <= NF; i++) {
      p = index($i, "=")
      if (p > 0 && substr($i, 1, p - 1) == name) {
        return substr($i, p + 1)
      }
    }
    return ""
  }

  function keep_sample(kind, row) {
    if (sample_count[kind] < samples) {
      sample_count[kind]++
      sample[kind, sample_count[kind]] = row
    }
  }

  function method_key(symbol,    key) {
    key = symbol
    sub(/\$.*/, "", key)
    return key
  }

  function emitted_owner_of(emitted,    owner) {
    owner = emitted
    sub(/\$H.*/, "", owner)
    return owner
  }

  /^\[MAT_METHOD_EXIT\]/ {
    method_exit_rows++
    reason = field("reason")
    full = field("full")
    override = field("override")
    class_name = field("class")
    method_name = field("method")
    if (full != "") {
      exact_exit_reason[full] = reason
      exact_exit_rows[full]++
    }
    if (override != "") {
      exact_exit_reason[override] = reason
      exact_exit_rows[override]++
    }
    key = class_name "#" method_name
    base_exit_reason[key] = reason
    base_exit_rows[key]++
    next
  }

  /^\[MAT_METHOD_ENTRY\]/ {
    method_entry_rows++
    class_name = field("class")
    method_name = field("method")
    key = class_name "#" method_name
    base_entry_rows[key]++
    next
  }

  /^\[MAT_METHOD_NAME\]/ {
    method_name_rows++
    class_name = field("class")
    method_name = field("method")
    base = field("base")
    full = field("full")
    candidate = field("candidate")
    key = class_name "#" method_name
    if (full != "") {
      exact_name_rows[full]++
      full_to_base[full] = base
    }
    if (base != "") {
      base_name_rows[base]++
      if (base_name_sample_count[base] < 3) {
        base_name_sample_count[base]++
        if (base_name_samples[base] == "") {
          base_name_samples[base] = full
        } else {
          base_name_samples[base] = base_name_samples[base] "," full
        }
      }
    }
    base_name_rows[key]++
    if (base_name_sample_count[key] < 3) {
      base_name_sample_count[key]++
      if (base_name_samples[key] == "") {
        base_name_samples[key] = full
      } else {
        base_name_samples[key] = base_name_samples[key] "," full
      }
    }
    next
  }

  /^\[MAT_METHOD_CALL\]/ {
    method_call_rows++
    body = field("body")
    requested_name = field("requested")
    owner = field("owner")
    method_name = field("method")
    override_name = field("override")
    key = owner "#" method_name
    if (body != "") {
      call_body_rows[body]++
      call_body_owner[body] = owner
      call_body_method[body] = method_name
      call_body_override[body] = override_name
    }
    if (requested_name != "") {
      call_requested_rows[requested_name]++
      if (call_requested_sample_count[requested_name] < 3) {
        call_requested_sample_count[requested_name]++
        sample_value = body "|" owner "#" method_name "|" override_name
        if (call_requested_samples[requested_name] == "") {
          call_requested_samples[requested_name] = sample_value
        } else {
          call_requested_samples[requested_name] = call_requested_samples[requested_name] "," sample_value
        }
      }
    }
    call_base_rows[key]++
    next
  }

  /^\[MAT_PRECALL\]/ {
    precall_rows++
    stage = field("stage")
    body = field("body")
    requested_name = field("requested")
    owner = field("owner")
    override_name = field("override")
    if (body != "" && stage != "") {
      precall_body_stage[body, stage]++
      precall_body_owner[body] = owner
      precall_body_override[body] = override_name
      if (precall_body_samples[body] == "") {
        precall_body_samples[body] = stage
      } else {
        precall_body_samples[body] = precall_body_samples[body] "," stage
      }
    }
    if (requested_name != "" && stage != "") {
      precall_requested_stage[requested_name, stage]++
      if (precall_requested_samples[requested_name] == "") {
        precall_requested_samples[requested_name] = stage "|" body
      } else if (precall_requested_sample_count[requested_name] < 5) {
        precall_requested_samples[requested_name] = precall_requested_samples[requested_name] "," stage "|" body
      }
      precall_requested_sample_count[requested_name]++
    }
    next
  }

  /^\[MAT_TX\]/ {
    tx = field("tx")
    if (tx == "") next
    phase[tx] = field("phase")
    requested[tx] = field("requested")
    target[tx] = field("target")
    state_key[tx] = field("state_key")
    body_symbol[tx] = field("body_symbol")
    identity_status[tx] = field("identity_status")
    symbol_relation[tx] = field("symbol_relation")
    required_contract[tx] = field("required_contract")
    branch[tx] = field("branch")
    selected_owner[tx] = field("selected_owner")
    materialization_action[tx] = field("materialization_action")
    body_function_present[tx] = field("body_function_present")
    body_has_body[tx] = field("body_has_body")
    body_state[tx] = field("body_state")
    next
  }

  /^\[MAT_DONE\]/ {
    key = field("requested") "|" field("target") "|" field("materialized")
    done_seen[key] = 1
    done_has_function[key] = field("has_function")
    done_has_body[key] = field("has_body")
    done_state[key] = field("state")
    done_status[key] = field("status")
    done_reason[key] = field("reason")
    done_producer_path[key] = field("producer_path")
    done_created_symbol_relation[key] = field("created_symbol_relation")
    next
  }

  /^\[MAT_EMIT\]/ {
    tx = field("tx")
    if (tx == "" || tx == "none") next
    kind = field("kind")
    body_present = field("body_present")
    lookup = field("lookup_present")
    module = field("module_present")
    plan = field("plan_present")
    emitted_flag = field("emitted_present")
    undefined = field("undefined_present")
    emitted = field("emitted")
    emit_required_contract = field("required_contract")
    emit_symbol_relation = field("symbol_relation")
    emit_identity_status = field("identity_status")

    if (body_present == "0" &&
        kind == "extern" &&
        required_contract[tx] == "none" &&
        symbol_relation[tx] == "all_equal" &&
        identity_status[tx] == "exact" &&
        materialization_action[tx] == "created_body" &&
        emit_required_contract == required_contract[tx] &&
        emit_symbol_relation == symbol_relation[tx] &&
        emit_identity_status == identity_status[tx]) {
      residual_rows++
      done_key = requested[tx] "|" target[tx] "|" body_symbol[tx]
      if (!(done_key in done_seen) && state_key[tx] != "") {
        done_key = requested[tx] "|" target[tx] "|" state_key[tx]
      }
      terminal = "no_exact_method_exit"
      base_key = method_key(body_symbol[tx])
      if (body_symbol[tx] in exact_exit_reason) {
        terminal = exact_exit_reason[body_symbol[tx]]
      } else {
        if (base_key in base_exit_reason) {
          terminal = "base_only_" base_exit_reason[base_key]
        } else if (body_symbol[tx] in exact_name_rows) {
          terminal = "no_exact_matching_full_name_without_exit"
        } else if (base_key in base_name_rows) {
          terminal = "no_exact_sibling_full_name"
        } else if (body_symbol[tx] in call_body_rows) {
          terminal = "no_exact_call_exact_without_entry"
        } else if (requested[tx] in call_requested_rows) {
          terminal = "no_exact_requested_call_symbol_mismatch"
        } else if ((body_symbol[tx], "after_arity") in precall_body_stage) {
          terminal = "no_exact_after_arity_no_call"
        } else if ((body_symbol[tx], "before_arity") in precall_body_stage) {
          terminal = "no_exact_before_arity_no_call"
        } else if ((body_symbol[tx], "inside_namespace") in precall_body_stage) {
          terminal = "no_exact_inside_namespace_no_call"
        } else if ((body_symbol[tx], "inside_type_params") in precall_body_stage) {
          terminal = "no_exact_inside_type_params_no_call"
        } else if ((body_symbol[tx], "after_tx") in precall_body_stage) {
          terminal = "no_exact_after_tx_no_call"
        } else if ((requested[tx], "after_arity") in precall_requested_stage) {
          terminal = "no_exact_requested_after_arity_symbol_mismatch"
        } else if ((requested[tx], "before_arity") in precall_requested_stage) {
          terminal = "no_exact_requested_before_arity_symbol_mismatch"
        } else if ((requested[tx], "inside_namespace") in precall_requested_stage) {
          terminal = "no_exact_requested_inside_namespace_symbol_mismatch"
        } else if ((requested[tx], "inside_type_params") in precall_requested_stage) {
          terminal = "no_exact_requested_inside_type_params_symbol_mismatch"
        } else if ((requested[tx], "after_tx") in precall_requested_stage) {
          terminal = "no_exact_requested_after_tx_symbol_mismatch"
        } else if (base_key in base_entry_rows) {
          terminal = "no_exact_entry_without_name"
        } else {
          terminal = "no_exact_no_call"
        }
      }
      cause = "lower_method_terminal_" terminal
      cause_count[cause]++
      group_key = cause "|" phase[tx] "|" branch[tx] "|" done_producer_path[done_key] "|" done_created_symbol_relation[done_key] "|" emitted_owner_of(emitted)
      group_count[group_key]++
      if (!(group_key in group_seen)) {
        group_seen[group_key] = 1
        group_order[++group_total] = group_key
        group_cause[group_key] = cause
      }
      row = "cause=" cause " tx=" tx " requested=" requested[tx] " body=" body_symbol[tx] " branch=" branch[tx] " producer=" done_producer_path[done_key] " created_relation=" done_created_symbol_relation[done_key] " exact_exit_rows=" (exact_exit_rows[body_symbol[tx]] + 0) " base_exit_rows=" (base_exit_rows[base_key] + 0) " exact_name_rows=" (exact_name_rows[body_symbol[tx]] + 0) " base_name_rows=" (base_name_rows[base_key] + 0) " base_entry_rows=" (base_entry_rows[base_key] + 0) " call_body_rows=" (call_body_rows[body_symbol[tx]] + 0) " call_requested_rows=" (call_requested_rows[requested[tx]] + 0) " call_owner=" call_body_owner[body_symbol[tx]] " call_method=" call_body_method[body_symbol[tx]] " call_override=" call_body_override[body_symbol[tx]] " precall_body_stages=" precall_body_samples[body_symbol[tx]] " precall_requested_stages=" precall_requested_samples[requested[tx]] " precall_owner=" precall_body_owner[body_symbol[tx]] " precall_override=" precall_body_override[body_symbol[tx]] " sibling_fulls=" base_name_samples[base_key] " requested_call_samples=" call_requested_samples[requested[tx]]
      keep_sample("residual", row)
    }
  }

  END {
    selected_rows = -1
    selected_cause = ""
    for (cause in cause_count) {
      cause_kinds++
      rows = cause_count[cause] + 0
      if (rows <= max_class_rows) root_sized_cause_count++
      if (rows > selected_rows || (rows == selected_rows && (selected_cause == "" || cause < selected_cause))) {
        selected_cause = cause
        selected_rows = rows
      }
    }
    for (i = 1; i <= group_total; i++) {
      key = group_order[i]
      if ((group_count[key] + 0) <= max_class_rows) root_sized_groups++
    }

    if ((residual_rows + 0) == 0) {
      classification = "no_lower_method_terminal_residual"
    } else if ((method_exit_rows + 0) == 0) {
      classification = "rejected_no_method_exit_probe_rows"
    } else if (cause_kinds > 1) {
      classification = "rejected_mixed_lower_method_terminals"
    } else if (selected_rows > max_class_rows || selected_rows == 0) {
      classification = "rejected_lower_method_terminal_class_too_wide"
    } else {
      classification = "eligible_lower_method_terminal_edge"
    }

    print ""
    print "## LowerMethod Terminal Counts"
    print "method_entry_rows=" method_entry_rows + 0
    print "method_name_rows=" method_name_rows + 0
    print "method_call_rows=" method_call_rows + 0
    print "precall_rows=" precall_rows + 0
    print "method_exit_rows=" method_exit_rows + 0
    print "residual_rows=" residual_rows + 0
    print "terminal_cause_kinds=" cause_kinds + 0
    print "terminal_groups=" group_total + 0
    print "terminal_root_sized_groups=" root_sized_groups + 0
    print ""
    print "## LowerMethod Terminal Classification"
    print "selected_cause=" selected_cause
    print "selected_rows=" selected_rows + 0
    print "classification=" classification
    print "[GENERATED_STAGE_LOWER_METHOD_TERMINAL] owner=MaterializationTransaction old_edge=instance_class_info_lower_method_created_none classification=" classification " selected_cause=" selected_cause " selected_rows=" (selected_rows + 0)
    print ""
    print "## Terminal Buckets"
    if (cause_kinds == 0) {
      print "(none)"
    } else {
      for (cause in cause_count) {
        print "cause=" cause " rows=" cause_count[cause] + 0 " root_sized=" (((cause_count[cause] + 0) <= max_class_rows) ? 1 : 0)
      }
    }
    print ""
    print "## Terminal Groups"
    if (group_total == 0) {
      print "(none)"
    } else {
      for (i = 1; i <= group_total; i++) {
        key = group_order[i]
        print "group=" key " rows=" group_count[key] + 0 " root_sized=" (((group_count[key] + 0) <= max_class_rows) ? 1 : 0) " cause=" group_cause[key]
      }
    }
    print ""
    print "## Terminal Residual Samples"
    if ((sample_count["residual"] + 0) == 0) {
      print "(none)"
    } else {
      for (i = 1; i <= sample_count["residual"]; i++) print sample["residual", i]
    }
  }
' "$log_file" | tee "$SUMMARY_LOG"

terminal_classification="$(awk -F= '$1 == "classification" { value = $2 } END { print value }' "$SUMMARY_LOG")"

if [[ -n "$kept_classifier_tmp" && -d "$kept_classifier_tmp" && "${KEEP_TMP:-0}" != "1" ]]; then
  rm -rf "$kept_classifier_tmp"
fi
if [[ -n "$nested_tmp" && -d "$nested_tmp" && "${KEEP_TMP:-0}" != "1" ]]; then
  rm -rf "$nested_tmp"
fi

if [[ "${REQUIRE_REACHED:-0}" == "1" && "$classifier_classification" != "reached_tx_and_emit" ]]; then
  echo "FAIL: nested classifier did not reach [MAT_EMIT]" >&2
  exit 9
fi

if [[ "${REQUIRE_ROOT_SIZED:-0}" == "1" &&
      "$terminal_classification" != "eligible_lower_method_terminal_edge" ]]; then
  echo "FAIL: no root-sized lower_method terminal edge selected" >&2
  exit 9
fi
