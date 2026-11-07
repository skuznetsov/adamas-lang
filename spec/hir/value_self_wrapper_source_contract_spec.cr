require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

private record ValueSelfWrapperObservation,
  receiver_owner : String,
  nilary_call_name : String?,
  nilary_call_type : Adamas::HIR::TypeRef?,
  target_name_is_concrete : Bool,
  target_registry_def_is_object_source : Bool,
  target_registry_arena_is_object_source : Bool,
  lexical_source_still_exact : Bool,
  source_return_def_stamp_is_object_source : Bool,
  source_return_arena_stamp_is_object_source : Bool,
  wrapper_self_call_name : String?,
  wrapper_self_call_arity : Int32,
  wrapper_self_call_type : Adamas::HIR::TypeRef?,
  required_sibling_preserved : Bool

private record ValueSelfWrapperGuardObservation,
  exact_source_accepted : Bool,
  stale_def_rejected : Bool,
  stale_arena_rejected : Bool,
  replacement_def_has_replacement_owner : Bool,
  crossed_def_arena_rejected : Bool,
  reference_receiver_rejected : Bool,
  ordinary_body_rejected : Bool,
  abstract_source_rejected : Bool,
  method_mismatch_rejected : Bool,
  typed_suffix_rejected : Bool

class Adamas::HIR::AstToHir
  def __test_register_value_self_wrapper_sources(
    parent : Adamas::Compiler::Frontend::ClassNode,
    parent_arena : Adamas::Compiler::Frontend::ArenaLike,
    child_classes : Array(Adamas::Compiler::Frontend::ClassNode),
    child_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    @arena = parent_arena
    register_class(parent)
    @arena = child_arena
    child_classes.each { |node| register_class(node) }
  end

  def __test_value_self_source_def(name : String) : Adamas::Compiler::Frontend::DefNode
    @function_defs[name]? || raise "missing parsed source Def #{name}"
  end

  def __test_value_self_source_arena_for(def_node : Adamas::Compiler::Frontend::DefNode) : Adamas::Compiler::Frontend::ArenaLike?
    registered_arena_for_def(def_node)
  end

  def __test_value_self_reference_type : TypeRef
    type_ref_for_name("ValueSelfReference")
  end

  def __test_finish_value_self_wrapper_materialization : Nil
    lower_missing_call_targets
    process_pending_lower_functions
  end

  def __test_value_self_wrapper_contract(
    object_def : Adamas::Compiler::Frontend::DefNode,
    object_arena : Adamas::Compiler::Frontend::ArenaLike,
    required_arg_def : Adamas::Compiler::Frontend::DefNode,
    required_arg_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : ValueSelfWrapperObservation
    lower_function_if_needed("UInt64#observed")
    process_pending_lower_functions
    # Match the full HIR flush: consumers are first lowered and drained, then
    # the missing-call safety net materializes calls discovered in those bodies.
    # The follow-up drain completes the target before its source stamps are read.
    __test_finish_value_self_wrapper_materialization

    observed = @module.function_by_name("UInt64#observed") ||
               raise "missing lowered UInt64 observer"
    nilary_call = observed.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name.starts_with?("UInt64#metric") && call.args.empty? }
    target_name = nilary_call.try(&.method_name)
    target = target_name.try { |name| @module.function_by_name(name) }
    wrapper_self_call = target.try do |function|
      function.blocks.flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .find { |call| call.method_name.starts_with?("UInt64#metric") && call.args.size == 1 }
    end
    sibling_name = @function_defs.find do |registered_name, definition|
      registered_name != "UInt64#metric" &&
        registered_name.includes?("$arity1") && definition.same?(required_arg_def)
    end.try(&.[0])

    ValueSelfWrapperObservation.new(
      get_type_name_from_ref(TypeRef::UINT64),
      target_name,
      nilary_call.try(&.type),
      target_name.try(&.starts_with?("UInt64#metric")) || false,
      target_name.try { |name| @function_defs[name]?.try(&.same?(object_def)) == true } || false,
      target_name.try { |name| @function_def_arenas[name]?.try(&.same?(object_arena)) == true } || false,
      @function_defs["Object#metric"]?.try(&.same?(object_def)) == true &&
        @function_def_arenas["Object#metric"]?.try(&.same?(object_arena)) == true,
      target.try(&.source_return_definition_id) == object_def.object_id.to_u64,
      target.try(&.source_return_arena_key) == arena_map_key(object_arena),
      wrapper_self_call.try(&.method_name),
      wrapper_self_call.try(&.args.size) || -1,
      wrapper_self_call.try(&.type),
      sibling_name != nil &&
        @function_defs[sibling_name.not_nil!]?.try(&.same?(required_arg_def)) == true &&
        @function_def_arenas[sibling_name.not_nil!]?.try(&.same?(required_arg_arena)) == true,
    )
  end

  def __test_value_self_wrapper_guard(
    requested_name : String,
    source_name : String,
    source_def : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
    receiver_type : TypeRef,
  ) : Bool
    preserve_requested_value_self_redispatch_wrapper_owner?(
      requested_name, source_name, source_def, source_arena, receiver_type,
    )
  end

  def __test_value_self_wrapper_guard_cases(
    object_def : Adamas::Compiler::Frontend::DefNode,
    object_arena : Adamas::Compiler::Frontend::ArenaLike,
    replacement_def : Adamas::Compiler::Frontend::DefNode,
    replacement_arena : Adamas::Compiler::Frontend::ArenaLike,
    wrong_arena : Adamas::Compiler::Frontend::ArenaLike,
    ordinary_def : Adamas::Compiler::Frontend::DefNode,
    abstract_def : Adamas::Compiler::Frontend::DefNode,
    other_method_def : Adamas::Compiler::Frontend::DefNode,
    reference_type : TypeRef,
  ) : ValueSelfWrapperGuardObservation
    target = "UInt64#metric"
    source_name = "Object#metric"
    receiver = TypeRef::UINT64
    exact_source_accepted = __test_value_self_wrapper_guard(
      target, source_name, object_def, object_arena, receiver,
    )
    stale_def_rejected = !__test_value_self_wrapper_guard(
      target, source_name, replacement_def, object_arena, receiver,
    )
    stale_arena_rejected = !__test_value_self_wrapper_guard(
      target, source_name, object_def, replacement_arena, receiver,
    ) && !__test_value_self_wrapper_guard(
      target, source_name, object_def, wrong_arena, receiver,
    )

    # Simulate a registry replacement where the Def was parsed in one Arena but
    # is paired with another Arena under the lexical Object key. Record the
    # replacement's actual Def owner independently before crossing the named
    # registry pair, so the control distinguishes source provenance from the
    # two name-indexed fields that the guard receives.
    registered_def = @function_defs[source_name]? || raise "missing Object#metric registry entry"
    registered_arena = @function_def_arenas[source_name]? || raise "missing Object#metric Arena entry"
    crossed_def_arena_rejected = false
    replacement_def_has_replacement_owner = false
    begin
      @def_node_arenas[replacement_def.object_id] = {replacement_def, replacement_arena}
      replacement_def_has_replacement_owner =
        __test_value_self_source_arena_for(replacement_def).try(&.same?(replacement_arena)) == true
      @function_defs[source_name] = replacement_def
      @function_def_arenas[source_name] = object_arena
      crossed_def_arena_rejected = !__test_value_self_wrapper_guard(
        target, source_name, replacement_def, object_arena, receiver,
      )
    ensure
      @function_defs[source_name] = registered_def
      @function_def_arenas[source_name] = registered_arena
    end

    ValueSelfWrapperGuardObservation.new(
      exact_source_accepted,
      stale_def_rejected,
      stale_arena_rejected,
      replacement_def_has_replacement_owner,
      crossed_def_arena_rejected,
      !__test_value_self_wrapper_guard(
        "ValueSelfReference#metric", source_name, object_def, object_arena, reference_type,
      ),
      !__test_value_self_wrapper_guard(
        "UInt64#constant_metric", "Object#constant_metric", ordinary_def, object_arena, receiver,
      ),
      !__test_value_self_wrapper_guard(
        "UInt64#abstract_metric", "Object#abstract_metric", abstract_def, object_arena, receiver,
      ),
      !__test_value_self_wrapper_guard(
        target, "Object#other_metric", other_method_def, object_arena, receiver,
      ),
      !__test_value_self_wrapper_guard(
        "UInt64#metric$UInt64", source_name, object_def, object_arena, receiver,
      ),
    )
  end
end

private def parse_value_self_wrapper_program(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program
end

private def value_self_wrapper_contract_fixture
  parent_source = <<-CRYSTAL
    abstract class Object
      def metric : UInt64
        metric(7_u64)
      end

      def constant_metric : UInt64
        11_u64
      end

      def other_metric : UInt64
        other_metric(8_u64)
      end

      abstract def abstract_metric : UInt64
    end
  CRYSTAL
  child_source = <<-CRYSTAL
    struct Value
    end

    struct Number
    end

    struct Int
    end

    struct UInt64
      def metric(item)
        item
      end

      def observed : UInt64
        self.metric
      end

      def one_argument : UInt64
        self.metric(9_u64)
      end
    end

    class ValueSelfReference < Object
    end
  CRYSTAL
  replacement_source = <<-CRYSTAL
    class Object
      def metric : UInt64
        metric(7_u64)
      end
    end
  CRYSTAL

  parent_program = parse_value_self_wrapper_program(parent_source)
  parent_arena = parent_program.arena
  parent = parent_program.roots.compact_map do |root|
    parent_arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
  end.first? || raise "missing parsed Object source"

  child_program = parse_value_self_wrapper_program(child_source)
  child_arena = child_program.arena
  child_classes = child_program.roots.compact_map do |root|
    child_arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
  end

  replacement_program = parse_value_self_wrapper_program(replacement_source)
  replacement_arena = replacement_program.arena
  replacement_object = replacement_program.roots.compact_map do |root|
    replacement_arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
  end.first? || raise "missing replacement Object source"
  replacement_def = replacement_object.body.not_nil!.compact_map do |expr_id|
    replacement_arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
  end.find { |node| String.new(node.name) == "metric" } ||
                  raise "missing replacement metric Def"

  converter = Adamas::HIR::AstToHir.new(
    child_arena,
    sources_by_arena: {
      parent_arena.object_id.to_u64 => parent_source,
      child_arena.object_id.to_u64 => child_source,
      replacement_arena.object_id.to_u64 => replacement_source,
    },
  )
  converter.no_prelude = true
  converter.__test_register_value_self_wrapper_sources(parent, parent_arena, child_classes, child_arena)

  parent_defs = parent.body.not_nil!.compact_map do |expr_id|
    parent_arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
  end
  object_ast_def = parent_defs.find { |node| String.new(node.name) == "metric" } ||
                   raise "missing parsed Object#metric Def"
  object_def = converter.__test_value_self_source_def("Object#metric")
  raise "Object#metric registry did not retain its parsed Def" unless object_def.same?(object_ast_def)
  ordinary_def = converter.__test_value_self_source_def("Object#constant_metric")
  abstract_def = converter.__test_value_self_source_def("Object#abstract_metric")
  other_method_def = converter.__test_value_self_source_def("Object#other_metric")
  required_arg_def = converter.__test_value_self_source_def("UInt64#metric")
  parent_defs.size.should be > 0
  reference_type = converter.__test_value_self_reference_type
  {
    converter, parent_arena, child_arena, object_def, ordinary_def,
    abstract_def, other_method_def, required_arg_def, replacement_def,
    replacement_arena, reference_type,
  }
end

describe "value receiver Object self-redispatch source contract" do
  it "lowers the parsed Object wrapper under concrete UInt64 with the exact source receipt" do
    converter, parent_arena, child_arena, object_def, _ordinary_def, _abstract_def,
      _other_method_def, required_arg_def, _replacement_def, _replacement_arena,
      _reference_type = value_self_wrapper_contract_fixture
    parent_arena.object_id.should_not eq(child_arena.object_id)

    result = converter.__test_value_self_wrapper_contract(
      object_def, parent_arena, required_arg_def, child_arena,
    )
    result.receiver_owner.should eq("UInt64")
    result.nilary_call_name.should_not be_nil
    result.nilary_call_name.not_nil!.should start_with("UInt64#metric")
    result.nilary_call_type.should eq(Adamas::HIR::TypeRef::UINT64)
    result.target_name_is_concrete.should be_true
    result.target_registry_def_is_object_source.should be_true
    result.target_registry_arena_is_object_source.should be_true
    result.lexical_source_still_exact.should be_true
    result.source_return_def_stamp_is_object_source.should be_true
    result.source_return_arena_stamp_is_object_source.should be_true
    result.wrapper_self_call_name.should_not be_nil
    result.wrapper_self_call_name.not_nil!.should start_with("UInt64#metric")
    result.wrapper_self_call_arity.should eq(1)
    result.wrapper_self_call_type.should eq(Adamas::HIR::TypeRef::UINT64)
    result.required_sibling_preserved.should be_true
  end

  it "rejects stale, crossed-arena, reference, non-wrapper, abstract, mismatched, and suffixed witnesses" do
    converter, parent_arena, child_arena, object_def, ordinary_def, abstract_def,
      other_method_def, _required_arg_def, replacement_def, replacement_arena,
      reference_type = value_self_wrapper_contract_fixture
    result = converter.__test_value_self_wrapper_guard_cases(
      object_def, parent_arena, replacement_def, replacement_arena, child_arena, ordinary_def,
      abstract_def, other_method_def, reference_type,
    )

    result.exact_source_accepted.should be_true
    result.stale_def_rejected.should be_true
    result.stale_arena_rejected.should be_true
    result.replacement_def_has_replacement_owner.should be_true
    result.crossed_def_arena_rejected.should be_true
    result.reference_receiver_rejected.should be_true
    result.ordinary_body_rejected.should be_true
    result.abstract_source_rejected.should be_true
    result.method_mismatch_rejected.should be_true
    result.typed_suffix_rejected.should be_true
  end
end
