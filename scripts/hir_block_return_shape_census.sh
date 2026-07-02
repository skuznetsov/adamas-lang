#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/hir_block_return_shape_census.sh

Read-only census for Slice 0k-CP / 0k-CU.

It copies src/ to a temporary directory, injects default-off probes into the
temporary copy of ast_to_hir.cr, builds a temporary probe compiler, and counts
block-call wrapper names that observe multiple callsite block-return shapes.
The census is a falsifier for the proposed BlockCallReturnContract: if the
shape space is broad, production wrapper specialization remains rejected. It
also reports an assigned-tail passthrough discriminator for helpers shaped like
`result = yield; ...; result`.

Environment:
  CRYSTAL_BIN                         Crystal compiler used to build the temp probe (default: crystal).
  KEEP_TMP=1                          Keep temporary artifacts and print their paths.
  REQUIRE_CURRENT_CP_ROOT_SIZED=1      Exit nonzero unless the current census is root-sized.
  REQUIRE_CURRENT_CP_BROAD=1           Exit nonzero unless the current census is broad.
  REQUIRE_CURRENT_CU_CONTRACT=1        Exit nonzero unless the 0k-CU contract is applied.
  ROOT_SIZED_KEY_LIMIT=N               Max multi-return candidate keys for root-sized (default: 8).
  ROOT_SIZED_ADDITIONAL_BODY_LIMIT=N   Max extra return-shape bodies for root-sized (default: 32).

Classifications:
  current_0k_cp_hir_block_return_shape_root_sized
  current_0k_cp_hir_block_return_shape_broad
  current_0k_cu_block_call_return_contract_applied
  hir_block_return_shape_census_unmatched

This script is a census only. It does not edit tracked compiler source and is
not permission to patch timed_cp_phase, CopyPropagation, HIR/MIR/LLVM backend
block-return handling, Set/Hash delegates, workers, output, or BlockOwner.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/hir-block-return-shape-census.XXXXXX")"

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
ROOT_SIZED_KEY_LIMIT="${ROOT_SIZED_KEY_LIMIT:-8}"
ROOT_SIZED_ADDITIONAL_BODY_LIMIT="${ROOT_SIZED_ADDITIONAL_BODY_LIMIT:-32}"
TMP_SRC="$TMP_DIR/src"
PROBE_BIN="$TMP_DIR/adamas_block_return_shape_probe"
BUILD_LOG="$TMP_DIR/build.log"
RUN_LOG="$TMP_DIR/run.log"
SUMMARY_LOG="$TMP_DIR/summary.log"
HIR_BASE="$TMP_DIR/block_return_shape_hir"

echo "# HIR Block Return Shape Census"
echo "repo=$ROOT_DIR"
echo "crystal_bin=$CRYSTAL_BIN"
echo "root_sized_key_limit=$ROOT_SIZED_KEY_LIMIT"
echo "root_sized_additional_body_limit=$ROOT_SIZED_ADDITIONAL_BODY_LIMIT"
echo "require_current_cp_root_sized=${REQUIRE_CURRENT_CP_ROOT_SIZED:-0}"
echo "require_current_cp_broad=${REQUIRE_CURRENT_CP_BROAD:-0}"
echo "require_current_cu_contract=${REQUIRE_CURRENT_CU_CONTRACT:-0}"
echo "note: temp-source-copy census; tracked compiler source is not edited"

cp -R "$ROOT_DIR/src" "$TMP_SRC"

AST_FILE="$TMP_SRC/compiler/hir/ast_to_hir.cr"
ruby - "$AST_FILE" <<'RUBY'
path = ARGV.fetch(0)
src = File.read(path)

helper_anchor = "    private def record_block_return_type_for_call(\n"
helper = <<'CRYSTAL'
    private def block_return_census_identifier_name(expr_id : ExprId) : String?
      loop do
        node = @arena[expr_id]
        case node
        when Adamas::Compiler::Frontend::GroupingNode
          expr_id = node.expression
        when Adamas::Compiler::Frontend::MacroExpressionNode
          expr_id = node.expression
        when Adamas::Compiler::Frontend::IdentifierNode
          return safe_slice_to_string(node.name)
        else
          return nil
        end
      end
    end

    private def block_return_census_tail_identifier_name(expr_id : ExprId) : String?
      loop do
        node = @arena[expr_id]
        case node
        when Adamas::Compiler::Frontend::GroupingNode
          expr_id = node.expression
        when Adamas::Compiler::Frontend::MacroExpressionNode
          expr_id = node.expression
        when Adamas::Compiler::Frontend::BeginNode
          if clauses = node.rescue_clauses
            return nil unless clauses.empty?
          end
          return nil if node.else_body
          return nil if node.body.empty?
          expr_id = node.body.last
        when Adamas::Compiler::Frontend::IdentifierNode
          return safe_slice_to_string(node.name)
        else
          return nil
        end
      end
    end

    private def block_return_census_assigned_yield_tail_passthrough?(body : Array(ExprId)) : Bool
      return false if body.empty?
      tail_name = block_return_census_tail_identifier_name(body.last)
      return false unless tail_name && !tail_name.empty?

      assigned_from_yield = false
      body.each do |expr_id|
        node = @arena[expr_id]
        case node
        when Adamas::Compiler::Frontend::AssignNode
          target_name = block_return_census_identifier_name(node.target)
          next unless target_name == tail_name
          assigned_from_yield = yield_return_expr?(node.value)
        end
      end
      assigned_from_yield
    end

    private def trace_block_return_shape_census(
      stage : String,
      mangled_method_name : String,
      base_method_name : String,
      block_return_name : String?,
    ) : Nil
      return unless env_get("ADAMAS_BLOCK_RETURN_SHAPE_CENSUS")

      raw_name = block_return_name || "nil"
      stable_name = stable_block_return_type_name(block_return_name) || raw_name
      func_def = @function_defs[mangled_method_name]? || @function_defs[base_method_name]?
      block_param_state = "none"
      contains_yield_value = false
      assigned_tail_passthrough_value = false
      has_def_value = false
      if defn = func_def
        has_def_value = true
        if params = defn.params
          if block_param = find_param(params) { |_p| _p.is_block }
            block_param_state = block_param.type_annotation.nil? ? "untyped" : "typed"
          end
        end

        initial_arena = @function_def_arenas[mangled_method_name]? ||
                        @function_def_arenas[strip_type_suffix(mangled_method_name)]? ||
                        @function_def_arenas[base_method_name]? ||
                        @function_def_arenas[strip_type_suffix(base_method_name)]? ||
                        @arena
        resolved_arena = arena_fits_def?(initial_arena, defn) ? initial_arena : resolve_arena_for_def(defn, initial_arena)
        contains_yield_value = def_contains_yield?(defn, resolved_arena)
        begin
          with_arena(resolved_arena) do
            if body = defn.body
              assigned_tail_passthrough_value = block_return_census_assigned_yield_tail_passthrough?(body)
            end
          end
        rescue
          assigned_tail_passthrough_value = false
        end
      end

      yield_return_value = yield_return_function_for_call(mangled_method_name, base_method_name)
      type_param_name = block_return_type_param_name(mangled_method_name, base_method_name)

      STDERR.puts "[BRC_CENSUS]\t#{stage}\t#{mangled_method_name}\t#{base_method_name}\t#{raw_name}\t#{stable_name}\t#{block_param_state}\t#{contains_yield_value ? 1 : 0}\t#{yield_return_value ? 1 : 0}\t#{has_def_value ? 1 : 0}\t#{type_param_name || "nil"}\t#{assigned_tail_passthrough_value ? 1 : 0}"
    end

CRYSTAL

unless src.include?(helper_anchor)
  warn "missing helper anchor"
  exit 2
end
src = src.sub(helper_anchor, helper + helper_anchor)

replacements = [
  [
    "      if block_return_name.nil? && block_for_inline\n        block_return_name = inline_block_return_type_name(block_for_inline, block_param_types_inline, @current_class)\n      end\n      if block_return_name\n",
    "      if block_return_name.nil? && block_for_inline\n" \
    "        block_return_name = inline_block_return_type_name(block_for_inline, block_param_types_inline, @current_class)\n" \
    "      end\n" \
    "      trace_block_return_shape_census(\"call\", mangled_method_name, base_method_name, block_return_name)\n" \
    "      if block_return_name\n",
  ],
  [
    "        if callsite_arg_types.any? { |t| t != TypeRef::VOID }\n          remember_callsite_arg_types(mangled_method_name, callsite_arg_types, callsite_arg_literals, callsite_arg_enum_names, has_block_call, has_named_args, call_named_arg_names)\n        end\n        record_block_return_type_for_call(mangled_method_name, base_method_name, block_return_name)\n",
    "        if callsite_arg_types.any? { |t| t != TypeRef::VOID }\n" \
    "          remember_callsite_arg_types(mangled_method_name, callsite_arg_types, callsite_arg_literals, callsite_arg_enum_names, has_block_call, has_named_args, call_named_arg_names)\n" \
    "        end\n" \
    "        trace_block_return_shape_census(\"record\", mangled_method_name, base_method_name, block_return_name)\n" \
    "        record_block_return_type_for_call(mangled_method_name, base_method_name, block_return_name)\n",
  ],
]

replacements.each do |before, after|
  unless src.include?(before)
    warn "missing instrumentation anchor"
    exit 3
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
ADAMAS_BLOCK_RETURN_SHAPE_CENSUS=1 ADAMAS_STOP_AFTER_HIR=1 \
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

ruby - "$RUN_LOG" "$ROOT_SIZED_KEY_LIMIT" "$ROOT_SIZED_ADDITIONAL_BODY_LIMIT" >"$SUMMARY_LOG" <<'RUBY'
run_log = ARGV.fetch(0)
key_limit = Integer(ARGV.fetch(1))
body_limit = Integer(ARGV.fetch(2))

Entry = Struct.new(
  :name,
  :base,
  :shapes,
  :raw_shapes,
  :block_param_states,
  :contains_yield,
  :yield_return,
  :has_def,
  :type_params,
  :assigned_tail_passthrough,
  keyword_init: true
)

entries = Hash.new do |h, k|
  h[k] = Entry.new(
    name: k,
    base: "",
    shapes: {},
    raw_shapes: {},
    block_param_states: {},
    contains_yield: false,
    yield_return: false,
    has_def: false,
    type_params: {},
    assigned_tail_passthrough: false
  )
end

total_rows = 0
call_rows = 0
record_rows = 0

File.foreach(run_log) do |line|
  next unless line.start_with?("[BRC_CENSUS]\t")
  total_rows += 1
  parts = line.chomp.split("\t", 12)
  next unless parts.size >= 11
  _, stage, name, base, raw, stable, block_state, contains_yield, yield_return, has_def, type_param, assigned_tail = parts
  assigned_tail ||= "0"

  if stage == "call"
    call_rows += 1
    next unless raw == "nil"
    shape = "nil"
  elsif stage == "record"
    record_rows += 1
    shape = stable
  else
    next
  end

  entry = entries[name]
  entry.base = base
  entry.shapes[shape] = true
  entry.raw_shapes[raw] = true
  entry.block_param_states[block_state] = true
  entry.contains_yield ||= contains_yield == "1"
  entry.yield_return ||= yield_return == "1"
  entry.has_def ||= has_def == "1"
  entry.type_params[type_param] = true
  entry.assigned_tail_passthrough ||= assigned_tail == "1"
end

nilish = ->(shape) { shape == "nil" || shape == "Nil" || shape == "Void" }
candidate = ->(entry) {
  entry.block_param_states.key?("untyped") && entry.contains_yield
}
assigned_tail_candidate = ->(entry) {
  candidate.call(entry) && entry.assigned_tail_passthrough
}

multi_shape = entries.values.select { |e| e.shapes.size > 1 }
candidate_multi = multi_shape.select { |e| candidate.call(e) }
nil_value_coexist = entries.values.select do |e|
  e.shapes.keys.any? { |s| nilish.call(s) } && e.shapes.keys.any? { |s| !nilish.call(s) }
end
candidate_nil_value = nil_value_coexist.select { |e| candidate.call(e) }
value_shape_multi = entries.values.select do |e|
  e.shapes.keys.reject { |s| nilish.call(s) }.uniq.size > 1
end
candidate_value_shape_multi = value_shape_multi.select { |e| candidate.call(e) }
assigned_tail_multi = multi_shape.select { |e| assigned_tail_candidate.call(e) }
assigned_tail_nil_value = nil_value_coexist.select { |e| assigned_tail_candidate.call(e) }
assigned_tail_value_shape_multi = value_shape_multi.select { |e| assigned_tail_candidate.call(e) }

additional_bodies = candidate_multi.map { |e| e.shapes.size - 1 }.sum
assigned_tail_additional_bodies = assigned_tail_multi.map { |e| e.shapes.size - 1 }.sum
timed_entries = entries.values.select { |e| e.name.include?("CopyPropagationPass#timed_cp_phase") || e.base.include?("CopyPropagationPass#timed_cp_phase") }
timed_multi = timed_entries.select { |e| e.shapes.size > 1 }
timed_nil_value = timed_entries.select do |e|
  e.shapes.keys.any? { |s| nilish.call(s) } && e.shapes.keys.any? { |s| !nilish.call(s) }
end
timed_assigned_tail = timed_entries.select { |e| e.assigned_tail_passthrough }
timed_set_return = timed_entries.select do |e|
  e.shapes.key?("Set(UInt32)") || e.name.include?("$String_Set(UInt32)_block")
end

classification =
  if timed_assigned_tail.size == 1 &&
     timed_set_return.any? &&
     timed_multi.empty? &&
     timed_nil_value.empty? &&
     assigned_tail_multi.empty? &&
     candidate_multi.size > key_limit &&
     additional_bodies > body_limit
    "current_0k_cu_block_call_return_contract_applied"
  elsif timed_nil_value.any? && candidate_multi.size <= key_limit && additional_bodies <= body_limit
    "current_0k_cp_hir_block_return_shape_root_sized"
  elsif timed_nil_value.any?
    "current_0k_cp_hir_block_return_shape_broad"
  else
    "hir_block_return_shape_census_unmatched"
  end

puts "total_census_rows=#{total_rows}"
puts "call_rows=#{call_rows}"
puts "record_rows=#{record_rows}"
puts "wrapper_keys_total=#{entries.size}"
puts "multi_shape_keys=#{multi_shape.size}"
puts "candidate_multi_shape_keys=#{candidate_multi.size}"
puts "nil_value_coexist_keys=#{nil_value_coexist.size}"
puts "candidate_nil_value_coexist_keys=#{candidate_nil_value.size}"
puts "value_shape_multi_keys=#{value_shape_multi.size}"
puts "candidate_value_shape_multi_keys=#{candidate_value_shape_multi.size}"
puts "candidate_additional_return_shape_bodies=#{additional_bodies}"
puts "assigned_tail_multi_shape_keys=#{assigned_tail_multi.size}"
puts "assigned_tail_nil_value_coexist_keys=#{assigned_tail_nil_value.size}"
puts "assigned_tail_value_shape_multi_keys=#{assigned_tail_value_shape_multi.size}"
puts "assigned_tail_additional_return_shape_bodies=#{assigned_tail_additional_bodies}"
puts "timed_cp_phase_keys=#{timed_entries.size}"
puts "timed_cp_phase_multi_shape_keys=#{timed_multi.size}"
puts "timed_cp_phase_nil_value_coexist_keys=#{timed_nil_value.size}"
puts "timed_cp_phase_assigned_tail_passthrough_keys=#{timed_assigned_tail.size}"
puts "timed_cp_phase_set_return_keys=#{timed_set_return.size}"
puts "classification=#{classification}"

puts "candidate_multi_shape_sample:"
candidate_multi
  .sort_by { |e| [-e.shapes.size, e.name] }
  .first(20)
  .each do |e|
    puts "  key=#{e.name}"
    puts "    base=#{e.base}"
    puts "    shapes=#{e.shapes.keys.sort.join(' || ')}"
    puts "    block_param=#{e.block_param_states.keys.sort.join(',')}"
    puts "    contains_yield=#{e.contains_yield ? 1 : 0} yield_return=#{e.yield_return ? 1 : 0} assigned_tail=#{e.assigned_tail_passthrough ? 1 : 0} type_params=#{e.type_params.keys.sort.join(',')}"
  end

puts "assigned_tail_multi_shape_sample:"
assigned_tail_multi
  .sort_by { |e| [-e.shapes.size, e.name] }
  .first(20)
  .each do |e|
    puts "  key=#{e.name}"
    puts "    base=#{e.base}"
    puts "    shapes=#{e.shapes.keys.sort.join(' || ')}"
    puts "    block_param=#{e.block_param_states.keys.sort.join(',')}"
    puts "    contains_yield=#{e.contains_yield ? 1 : 0} yield_return=#{e.yield_return ? 1 : 0} assigned_tail=#{e.assigned_tail_passthrough ? 1 : 0} type_params=#{e.type_params.keys.sort.join(',')}"
  end

puts "timed_cp_phase_shape_sample:"
timed_entries
  .sort_by { |e| e.name }
  .first(20)
  .each do |e|
    puts "  key=#{e.name}"
    puts "    base=#{e.base}"
    puts "    shapes=#{e.shapes.keys.sort.join(' || ')}"
    puts "    block_param=#{e.block_param_states.keys.sort.join(',')}"
    puts "    contains_yield=#{e.contains_yield ? 1 : 0} yield_return=#{e.yield_return ? 1 : 0} assigned_tail=#{e.assigned_tail_passthrough ? 1 : 0} type_params=#{e.type_params.keys.sort.join(',')}"
  end
RUBY

cat "$SUMMARY_LOG"

classification="$(awk -F= '$1 == "classification" { print $2; exit }' "$SUMMARY_LOG")"
echo "summary_log=$SUMMARY_LOG"
echo "run_log=$RUN_LOG"

if [[ "${REQUIRE_CURRENT_CP_ROOT_SIZED:-0}" == "1" &&
      "$classification" != "current_0k_cp_hir_block_return_shape_root_sized" ]]; then
  exit 23
fi
if [[ "${REQUIRE_CURRENT_CP_BROAD:-0}" == "1" &&
      "$classification" != "current_0k_cp_hir_block_return_shape_broad" ]]; then
  exit 24
fi
if [[ "${REQUIRE_CURRENT_CU_CONTRACT:-0}" == "1" &&
      "$classification" != "current_0k_cu_block_call_return_contract_applied" ]]; then
  exit 25
fi

exit 0
