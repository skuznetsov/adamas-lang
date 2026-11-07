require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  # Exercise ordinary source registration and exact Def/Arena selection. The
  # requested actual types enter through the same yield-inference API used by
  # source calls; this helper does not inject locals or lower method bodies.
  def __test_entry_scoped_source_yield_type_names(
    base_method_name : String,
    receiver_name : String,
    arg_type_names : Array(String) = [] of String,
  ) : Array(String)?
    arg_types = arg_type_names.map { |name| type_ref_for_name(name) }
    selected = lookup_function_def_for_call(
      base_method_name,
      arg_types.size,
      true,
      arg_types,
    ) || return nil
    registered_name, definition = selected
    source_arena = @function_def_arenas[registered_name]?
    return nil unless source_arena
    return nil unless registered_arena_for_def(definition).try(&.same?(source_arena))

    selected_target = SelectedCallTarget.new(registered_name, definition, source_arena)
    # Parse a real positional call shape for this pre-lowering API query.
    query_source = "entry_probe(#{arg_types.each_index.map { |index| "input_#{index}" }.join(", ")}) {}"
    query_parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(query_source))
    query = query_parser.parse_program
    raise query_parser.diagnostics.inspect unless query_parser.diagnostics.empty?
    call = query.arena[query.roots.last].as(Adamas::Compiler::Frontend::CallNode)
    inferred = block_param_types_for_call(
      registered_name,
      base_method_name,
      type_ref_for_name(receiver_name),
      arg_types,
      call_node: call,
      call_arena: query.arena,
      selected_source_target: selected_target,
    )
    inferred.try &.map { |type_ref| get_type_name_from_ref(type_ref) }
  end

  # Isolated guard-level test for the entry-alias rule. The selected source
  # Def/Arena and parsed body are real; only the formal's call input is supplied
  # explicitly because this helper is the pre-lowering boundary under test.
  def __test_entry_alias_source_type(
    base_method_name : String,
    formal_name : String,
    alias_name : String,
    actual_type_names : Array(String),
  ) : String?
    actual_types = actual_type_names.map { |name| type_ref_for_name(name) }
    actual_type = actual_types.first? || return nil
    selected = lookup_function_def_for_call(
      base_method_name,
      actual_types.size,
      true,
      actual_types,
    ) || return nil
    registered_name, definition = selected
    source_arena = @function_def_arenas[registered_name]?
    return nil unless source_arena
    return nil unless registered_arena_for_def(definition).try(&.same?(source_arena))
    body = definition.body || return nil

    alias_assignment = nil.as(ExprId?)
    with_arena(source_arena) do
      body.each do |statement|
        assignment = node_for_expr(statement).as?(Adamas::Compiler::Frontend::AssignNode)
        next unless assignment
        target = node_for_expr(assignment.target).as?(Adamas::Compiler::Frontend::IdentifierNode)
        value = node_for_expr(assignment.value).as?(Adamas::Compiler::Frontend::IdentifierNode)
        next unless target && value
        next unless safe_slice_to_string(target.name) == alias_name
        next unless safe_slice_to_string(value.name) == formal_name
        alias_assignment = statement
        break
      end
    end
    return nil unless alias_assignment

    old_def = @current_def_node
    old_body_context = @infer_body_context
    old_inputs = @source_body_inference_inputs
    begin
      @current_def_node = definition
      @infer_body_context = body
      @source_body_inference_inputs = SourceBodyInferenceInputs.new(
        definition,
        source_arena,
        body,
        {formal_name => actual_type},
      )
      inferred = with_arena(source_arena) do
        source_entry_type_before_alias(body, alias_assignment.not_nil!, formal_name)
      end
      inferred.try { |type_ref| get_type_name_from_ref(type_ref) }
    ensure
      @current_def_node = old_def
      @infer_body_context = old_body_context
      @source_body_inference_inputs = old_inputs
    end
  end
end

private def parse_nested_yield_entry_source(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  program.roots.each do |root|
    if node = program.arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    end
  end
  converter
end

describe "entry-scoped local types during nested yield inference" do
  it "keeps the entry type for an alias before a later self-referential write" do
    converter = parse_nested_yield_entry_source(<<-CRYSTAL)
      class FutureWriteEntryOwner
        def source(value, &)
          yield value
        end

        def project(seed, &)
          original = seed
          source(seed) do |value|
            seed -= 1
            yield original
          end
        end
      end
    CRYSTAL

    converter.__test_entry_scoped_source_yield_type_names(
      "FutureWriteEntryOwner#project",
      "FutureWriteEntryOwner",
      ["Pointer(Void)"],
    ).should eq(["Pointer(Void)"])
    converter.__test_entry_alias_source_type(
      "FutureWriteEntryOwner#project",
      "seed",
      "original",
      ["Pointer(Void)"],
    ).should eq("Pointer(Void)")
  end

  it "withholds the entry fact after a direct write before the alias" do
    converter = parse_nested_yield_entry_source(<<-CRYSTAL)
      class PriorDirectWriteEntryOwner
        def source(value, &)
          yield value
        end

        def project(seed, &)
          seed = 65_i64
          original = seed
          source(seed) do |value|
            yield original
          end
        end
      end
    CRYSTAL

    converter.__test_entry_alias_source_type(
      "PriorDirectWriteEntryOwner#project",
      "seed",
      "original",
      ["Pointer(Void)"],
    ).should be_nil
  end

  it "withholds the entry fact after a branch writes before aliasing" do
    converter = parse_nested_yield_entry_source(<<-CRYSTAL)
      class PriorBranchWriteEntryOwner
        def source(value, &)
          yield value
        end

        def project(seed, choose : Bool, &)
          if choose
            seed = 65_i64
          else
            seed = 66_i64
          end
          original = seed
          source(seed) do |value|
            yield original
          end
        end
      end
    CRYSTAL

    converter.__test_entry_alias_source_type(
      "PriorBranchWriteEntryOwner#project",
      "seed",
      "original",
      ["Pointer(Void)", "Bool"],
    ).should be_nil
  end

  it "withholds the entry fact after an unknown implicit call" do
    converter = parse_nested_yield_entry_source(<<-CRYSTAL)
      class UnknownPrefixEffectEntryOwner
        def touch
          nil
        end

        def project(seed, &)
          touch
          original = seed
          yield original
        end
      end
    CRYSTAL

    converter.__test_entry_alias_source_type(
      "UnknownPrefixEffectEntryOwner#project", "seed", "original", ["Pointer(Void)"]
    ).should be_nil
  end

  it "withholds the entry fact after a writable escape" do
    converter = parse_nested_yield_entry_source(<<-CRYSTAL)
      class EscapedPrefixEntryOwner
        def project(seed, &)
          escaped = pointerof(seed)
          original = seed
          yield original
        end
      end
    CRYSTAL

    converter.__test_entry_alias_source_type(
      "EscapedPrefixEntryOwner#project", "seed", "original", ["Pointer(Void)"]
    ).should be_nil
  end

  it "does not share one untyped Def's local summary across pointer actuals" do
    converter = parse_nested_yield_entry_source(<<-CRYSTAL)
      class SameUntypedEntryOwner
        def source(value, &)
          yield value
        end

        def project(seed, &)
          original = seed
          source(seed) do |value|
            yield original
          end
        end
      end
    CRYSTAL

    base = "SameUntypedEntryOwner#project"
    receiver = "SameUntypedEntryOwner"
    converter.__test_entry_scoped_source_yield_type_names(
      base, receiver, ["Pointer(Void)"]
    ).should eq(["Pointer(Void)"])
    converter.__test_entry_scoped_source_yield_type_names(
      base, receiver, ["Pointer(UInt8)"]
    ).should eq(["Pointer(UInt8)"])
    converter.__test_entry_scoped_source_yield_type_names(
      base, receiver, ["Pointer(Void)"]
    ).should eq(["Pointer(Void)"])
  end

  it "keeps local names isolated between overload Defs" do
    converter = parse_nested_yield_entry_source(<<-CRYSTAL)
      class DifferentSelectedEntryOwner
        def project(seed : Pointer(Void), &)
          original = seed
          yield original
        end

        def project(seed : Pointer(UInt8), &)
          original = seed
          yield original
        end
      end
    CRYSTAL

    base = "DifferentSelectedEntryOwner#project"
    receiver = "DifferentSelectedEntryOwner"
    converter.__test_entry_scoped_source_yield_type_names(
      base, receiver, ["Pointer(Void)"]
    ).should eq(["Pointer(Void)"])
    converter.__test_entry_scoped_source_yield_type_names(
      base, receiver, ["Pointer(UInt8)"]
    ).should eq(["Pointer(UInt8)"])
  end
end
