require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private record SourceBlockArgumentBindingObservation,
  selected_name : String,
  supplied_types : Array(String?),
  formal_bindings : Hash(String, String),
  string_result_matches : Bool?,
  int32_result_matches : Bool?

class Adamas::HIR::AstToHir
  # Exercise the real source named-argument binder, then feed its exact
  # selected Def/Arena proof to callback-result input binding.
  def __test_source_block_argument_binding(
    caller_method : String,
    alternate_arena : Adamas::Compiler::Frontend::ArenaLike? = nil,
  ) : Tuple(SourceBlockArgumentBindingObservation, Bool?, Bool?)
    owner_name = "SourceBlockArgumentBindingProbe"
    caller_name = "#{owner_name}.#{caller_method}"
    caller_defs = @function_defs.select do |name, _|
      name == caller_name || name.starts_with?("#{caller_name}$")
    end.values.uniq(&.object_id)
    raise "expected one registered caller #{caller_name}, got #{caller_defs.size}" unless caller_defs.size == 1

    caller_def = caller_defs.first
    caller_arena = registered_arena_for_def(caller_def) ||
                   raise "caller #{caller_name} has no registered source arena"
    body = caller_def.body || raise "caller #{caller_name} has no body"
    call_expr = body.last? || raise "caller #{caller_name} has an empty body"
    call = with_arena(caller_arena) do
      node_for_expr(call_expr).as?(Adamas::Compiler::Frontend::CallNode) ||
        raise "caller #{caller_name} tail must be a CallNode"
    end
    named_args = call.named_args || [] of Adamas::Compiler::Frontend::NamedArgument
    raise "caller #{caller_name} must exercise named argument binding" if named_args.empty?

    old_arena = @arena
    old_current_class = @current_class
    old_current_method = @current_method
    old_current_def = @current_def_node
    old_current_method_is_class = @current_method_is_class
    old_infer_self_type_name = @infer_self_type_name
    old_infer_body_context = @infer_body_context

    begin
      @arena = caller_arena
      @current_class = owner_name
      @current_method = caller_method
      @current_def_node = caller_def
      @current_method_is_class = true
      @infer_self_type_name = owner_name
      @infer_body_context = body

      function = @module.create_function("__source_block_argument_binding_probe", TypeRef::VOID)
      ctx = LoweringContext.new(function, @module, caller_arena)
      source_bindings = [] of SourceCallBinding
      bound = lower_source_named_args(
        ctx,
        call.args,
        named_args,
        "#{owner_name}.#{call_target_name(caller_arena, call)}",
        nil,
        !call.block.nil?,
        nil,
        caller_arena,
        nil,
        source_bindings,
      ) || raise "source binder did not select a declaration for #{caller_name}"
      source_binding = source_bindings.first? || raise "source binder did not publish its selected declaration"
      selected_name, selected_def = bound[1]
      selected_arena = registered_arena_for_def(selected_def) ||
                       raise "selected Def has no declaration arena"

      argument_types = bound[0].map { |value| enum_tracked_type(ctx, value) }
      formal_bindings = source_block_result_bindings(
        selected_def,
        selected_arena,
        selected_name,
        nil,
        argument_types,
        source_binding,
      )
      block_contract = source_block_result_contract_for_call(
        selected_def,
        selected_arena,
        selected_name,
        nil,
        argument_types,
        source_binding,
      )
      string_match = block_contract.try do |contract|
        source_block_result_pattern_matches_value?(type_ref_for_name("String"), false, contract.pattern)
      end
      int32_match = block_contract.try do |contract|
        source_block_result_pattern_matches_value?(TypeRef::INT32, false, contract.pattern)
      end
      slots = source_binding.supplied_types.map do |actual|
        actual.try { |value| proc_source_type_name(value.type_ref, value.type_literal) }
      end

      wrong_definition_rejected = nil.as(Bool?)
      wrong_arena_rejected = nil.as(Bool?)
      if sibling = registered_source_def("#{owner_name}.sibling")
        sibling_name, sibling_def, sibling_arena = sibling
        wrong_definition_rejected = source_binding_rejected_by?(
          source_binding, sibling_def, sibling_arena, sibling_name,
        )
      end
      if alternate = alternate_arena
        wrong_arena_rejected = source_binding_rejected_by?(
          source_binding, selected_def, alternate, selected_name,
        )
      end

      observation = SourceBlockArgumentBindingObservation.new(
        selected_name,
        slots,
        formal_bindings,
        string_match,
        int32_match,
      )
      {observation, wrong_definition_rejected, wrong_arena_rejected}
    ensure
      @arena = old_arena
      @current_class = old_current_class
      @current_method = old_current_method
      @current_def_node = old_current_def
      @current_method_is_class = old_current_method_is_class
      @infer_self_type_name = old_infer_self_type_name
      @infer_body_context = old_infer_body_context
    end
  end

  private def call_target_name(
    call_arena : Adamas::Compiler::Frontend::ArenaLike,
    call : Adamas::Compiler::Frontend::CallNode,
  ) : String
    callee = call_arena[call.callee]
    case callee
    when Adamas::Compiler::Frontend::IdentifierNode
      safe_slice_to_string(callee.name) || ""
    else
      raise "unsupported source-call callee #{callee.class}"
    end
  end

  private def registered_source_def(
    name : String,
  ) : Tuple(String, Adamas::Compiler::Frontend::DefNode, Adamas::Compiler::Frontend::ArenaLike)?
    entry = @function_defs.find do |registered_name, _|
      registered_name == name || registered_name.starts_with?("#{name}$")
    end
    return nil unless entry
    selected_name, definition = entry
    declaration_arena = registered_arena_for_def(definition) || return nil
    {selected_name, definition, declaration_arena}
  end

  private def source_binding_rejected_by?(
    binding : SourceCallBinding,
    definition : Adamas::Compiler::Frontend::DefNode,
    declaration_arena : Adamas::Compiler::Frontend::ArenaLike,
    selected_name : String,
  ) : Bool
    source_block_result_bindings(
      definition,
      declaration_arena,
      selected_name,
      nil,
      [] of TypeRef,
      binding,
    )
    false
  rescue LoweringError
    true
  end
end

private def parse_source_block_argument_binding_probe(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  parsed = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  converter = Adamas::HIR::AstToHir.new(
    parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source},
  )
  converter.arena = parsed.arena
  parsed.roots.each do |root_id|
    if node = parsed.arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    end
  end
  converter
end

private def source_block_argument_binding_source : String
  <<-CRYSTAL
    class SourceBlockArgumentBindingProbe
      def self.optional_default(value : T? = nil, *, marker : Int32, &block : -> T) : T forall T
        yield
      end

      def self.interior_default(*, first : T? = nil, value : T, last : String = "tail", &block : -> T) : T forall T
        yield
      end

      def self.constrained(value : T, &block : -> T) : T forall T
        yield
      end

      def self.sibling(value : U, &block : -> U) : U forall U
        yield
      end

      def self.bare_type_value(value : T, &block : -> T) : T forall T
        yield
      end

      def self.metaclass_restriction(value : T.class, &block : -> T) : T forall T
        yield
      end

      def self.fixed_before_rest(value : T, *rest : String, marker : Int32, &block : -> T) : T forall T
        yield
      end

      def self.rest_class(*values : T, marker : Int32, &block : -> T) : T forall T
        yield
      end

      def self.plain_rest(*values : T, marker : Int32, &block : -> T) : T forall T
        yield
      end

      def self.optional_default_caller
        optional_default(marker: 1) { 65 }
      end

      def self.interior_default_caller
        interior_default(value: 65) { 65 }
      end

      def self.constrained_caller
        constrained(value: 65) { "wrong" }
      end

      def self.bare_type_value_caller
        bare_type_value(value: Int32) { 65 }
      end

      def self.metaclass_restriction_caller
        metaclass_restriction(value: Int32) { 65 }
      end

      def self.fixed_before_rest_caller
        fixed_before_rest(65, "tail", marker: 1) { 65 }
      end

      def self.rest_class_caller
        rest_class(Int32, marker: 1) { Int32 }
      end

      def self.plain_rest_caller
        plain_rest(65, 66, marker: 1) { 65 }
      end
    end
  CRYSTAL
end

describe "source callback input binding from selected call arguments" do
  it "does not infer a forall from an omitted nullable default" do
    converter = parse_source_block_argument_binding_probe(source_block_argument_binding_source)
    observation, _, _ = converter.__test_source_block_argument_binding("optional_default_caller")

    observation.supplied_types.should eq([nil, "Int32"])
    observation.formal_bindings.has_key?("T").should be_false
  end

  it "keeps omitted interior named defaults aligned with later supplied formals" do
    converter = parse_source_block_argument_binding_probe(source_block_argument_binding_source)
    observation, _, _ = converter.__test_source_block_argument_binding("interior_default_caller")

    observation.supplied_types.should eq([nil, "Int32", nil])
    observation.formal_bindings["T"].should eq("Int32")
  end

  it "uses an explicit input forall to reject an incompatible callback result" do
    converter = parse_source_block_argument_binding_probe(source_block_argument_binding_source)
    observation, _, _ = converter.__test_source_block_argument_binding("constrained_caller")

    observation.formal_bindings["T"].should eq("Int32")
    observation.string_result_matches.should be_false
    observation.int32_result_matches.should be_true
  end

  it "preserves class-literal kind for bare T versus T.class restrictions" do
    converter = parse_source_block_argument_binding_probe(source_block_argument_binding_source)
    bare, _, _ = converter.__test_source_block_argument_binding("bare_type_value_caller")
    metaclass, _, _ = converter.__test_source_block_argument_binding("metaclass_restriction_caller")

    bare.formal_bindings["T"].should eq("Int32.class")
    metaclass.formal_bindings["T"].should eq("Int32")
  end

  it "keeps fixed forall input binding ahead of a real positional rest" do
    converter = parse_source_block_argument_binding_probe(source_block_argument_binding_source)
    observation, _, _ = converter.__test_source_block_argument_binding("fixed_before_rest_caller")

    observation.formal_bindings["T"].should eq("Int32")
    observation.supplied_types.first.should eq("Int32")
  end

  it "preserves class-literal kind and ordinary types through positional rest values" do
    converter = parse_source_block_argument_binding_probe(source_block_argument_binding_source)
    class_literal, _, _ = converter.__test_source_block_argument_binding("rest_class_caller")
    plain, _, _ = converter.__test_source_block_argument_binding("plain_rest_caller")

    class_literal.formal_bindings["T"].should eq("Int32.class")
    plain.formal_bindings["T"].should eq("Int32")
  end

  it "rejects a source binding paired with a different Def or declaration arena" do
    source = source_block_argument_binding_source
    converter = parse_source_block_argument_binding_probe(source)
    other_converter = parse_source_block_argument_binding_probe(source)
    _, wrong_definition_rejected, wrong_arena_rejected =
      converter.__test_source_block_argument_binding("constrained_caller", other_converter.arena)

    wrong_definition_rejected.should be_true
    wrong_arena_rejected.should be_true
  end
end
