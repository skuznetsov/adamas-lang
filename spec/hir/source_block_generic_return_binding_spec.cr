require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_source_block_owner_input_bindings(
    source_receiver : String,
    method_name : String = "owner_output",
  ) : Hash(String, String)
    owner = "SourceBlockOwnerReturnBindingProbe"
    template = @generic_templates[owner]
    with_arena(template.arena) do
      definition = template.node.body.not_nil!.compact_map do |member|
        node = @arena[member].as?(Adamas::Compiler::Frontend::DefNode)
        node if node && safe_slice_to_string(node.name) == method_name
      end.first
      selected = "#{owner}(Void).#{method_name}"
      proof = source_positional_call_binding(selected, definition, template.arena,
        [] of SourceCallArgument, source_receiver)
      source_block_result_bindings(definition, template.arena, selected,
        type_ref_for_name("#{owner}(Void)"), [] of TypeRef, proof)
    end
  end

  # Resolve a source declaration through the normal Def/Arena registry before
  # exercising callback-output binding. The test must not reconstruct a Def
  # from a method name or read its slices under the caller's arena.
  def __test_source_block_output_type_bindings(
    owner_name : String,
    method_name : String,
    block_return_name : String,
    input_bindings : Hash(String, String) = {} of String => String,
  ) : Hash(String, String)?
    selected_name = "#{owner_name}.#{method_name}"
    definitions = @function_defs.select do |name, _|
      name == selected_name || name.starts_with?("#{selected_name}$")
    end.values.uniq(&.object_id)
    if definitions.empty? && (template = @generic_templates[owner_name]?)
      with_arena(template.arena) do
        template.node.body.try &.each do |member|
          if definition = @arena[member].as?(Adamas::Compiler::Frontend::DefNode)
            definitions << definition if safe_slice_to_string(definition.name) == method_name
          end
        end
      end
    end
    raise "expected one registered source Def for #{selected_name}, got #{definitions.size}" unless definitions.size == 1

    definition = definitions.first
    declaration_arena = registered_arena_for_def(definition) || @generic_templates[owner_name]?.try(&.arena) ||
                        raise "source Def #{selected_name} has no registered declaration arena"
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = owner_name
    @current_namespace_override = owner_name
    begin
      with_arena(declaration_arena) do
        source_block_output_type_bindings(
          definition,
          owner_name,
          block_return_name,
          input_bindings,
        )
      end
    ensure
      @current_class = old_class
      @current_namespace_override = old_namespace
    end
  end
end

private def source_block_generic_return_binding_fixture : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class SourceBlockGenericReturnBindingProbe
      def self.bare(&block : -> T) : T forall T
        yield
      end

      def self.nullable(&block : -> T?) : T? forall T
        yield
      end

      def self.nullable_class(&block : -> T?) : T.class forall T
        T
      end

      def self.already_covered(&block : -> T | Int32 | Nil) : T.class forall T
        T
      end

      def self.formal_first(&block : -> T | Int32) : T.class forall T
        T
      end

      def self.array_item(&block : -> Array(T)) : T forall T
        yield.first
      end

      def self.array_value(&block : -> Array(T)) : Array(T) forall T
        yield
      end

      def self.tuple_value(&block : -> Tuple(T, U)) : Tuple(T, U) forall T, U
        yield
      end

      def self.repeated_value(&block : -> Tuple(T, T)) : Tuple(T, T) forall T
        yield
      end

      def self.proc_identity(&block : -> Proc(T, T)) : Proc(T, T) forall T
        yield
      end

      def self.prebound(value : T, &block : -> Array(T)) : T forall T
        value
      end
    end

    class SourceBlockOwnerReturnBindingProbe(T)
      def self.owner_output(&block : -> T) : T
        yield
      end

      def self.shadow_output(&block : -> T) : T forall T
        yield
      end
    end
    CRYSTAL

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
    if owner = parsed.arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(owner)
    end
  end
  converter
end

describe "source callback output generic binding" do
  it "distinguishes a bare source owner from a concrete or symbolic applied receiver" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_owner_input_bindings(
      "SourceBlockOwnerReturnBindingProbe",
    ).should eq({} of String => String)

    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_owner_input_bindings(
      "SourceBlockOwnerReturnBindingProbe(Int32)",
    ).should eq({"T" => "Int32"})

    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_owner_input_bindings(
      "SourceBlockOwnerReturnBindingProbe(T)",
    ).should eq({"T" => "T"})

    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_owner_input_bindings(
      "SourceBlockOwnerReturnBindingProbe(String)", "shadow_output",
    ).should eq({} of String => String)
  end

  it "does not infer a new value for a rigid symbolic receiver argument" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockOwnerReturnBindingProbe", "owner_output", "String", {"T" => "T"},
    ).should be_nil
  end

  it "infers an unbound owner variable without requiring method forall" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockOwnerReturnBindingProbe", "owner_output", "Int32",
    ).should eq({"T" => "Int32"})
  end

  it "keeps a concrete owner variable authoritative during structural inference" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockOwnerReturnBindingProbe", "owner_output", "Int32", {"T" => "Int32"},
    ).should eq({"T" => "Int32"})

    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockOwnerReturnBindingProbe", "owner_output", "String", {"T" => "Int32"},
    ).should be_nil

    converter = source_block_generic_return_binding_fixture
    # Void can discard a callback result at the admission boundary. Structural
    # inference must still not reinterpret its established owner binding as a
    # free variable and replace it with Int32.
    converter.__test_source_block_output_type_bindings(
      "SourceBlockOwnerReturnBindingProbe", "owner_output", "Int32", {"T" => "Void"},
    ).should be_nil
  end

  it "binds a bare output-only formal from concrete, Nil, and metaclass results" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "bare", "Int32",
    ).should eq({"T" => "Int32"})

    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "bare", "Nil",
    ).should eq({"T" => "Nil"})

    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "bare", "Int32.class",
    ).should eq({"T" => "Int32.class"})
  end

  it "binds nullable output formals from either the value arm or Nil" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "nullable", "Int32",
    ).should eq({"T" => "Int32"})

    converter = source_block_generic_return_binding_fixture
    # Crystal's parsed T? restriction is the ordered union T | Nil. Matching
    # Nil against that source restriction binds the free T to Nil.
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "nullable", "Nil",
    ).should eq({"T" => "Nil"})
  end

  it "matches actual unions by consuming concrete nullable arms before binding the residual" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "nullable_class", "Int32 | Nil",
    ).should eq({"T" => "Int32"})
  end

  it "retains a class result's kind when its free formal is under a nullable output" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "nullable", "Int32.class",
    ).should eq({"T" => "Int32.class"})
  end

  it "retains kind in Proc formal slots and rejects a repeated formal with a different kind" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "proc_identity", "Proc(Int32.class, Int32.class)",
    ).should eq({"T" => "Int32.class"})

    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "proc_identity", "Proc(Int32.class, Int32)",
    ).should be_nil
  end

  it "rejects a free formal when concrete arms cover the entire actual union" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "already_covered", "Int32 | Nil",
    ).should be_nil
  end

  it "matches a singleton against source union arms in declaration order" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "formal_first", "Int32",
    ).should eq({"T" => "Int32"})
  end

  it "binds nested generic output formals without confusing the method return shape" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "array_item", "Array(Int32)",
    ).should eq({"T" => "Int32"})

    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "array_value", "Array(Int32)",
    ).should eq({"T" => "Int32"})
  end

  it "binds distinct tuple formals and rejects inconsistent repeated formals" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "tuple_value", "Tuple(Int32, String)",
    ).should eq({"T" => "Int32", "U" => "String"})

    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "repeated_value", "Tuple(Int32, Int32)",
    ).should eq({"T" => "Int32"})

    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "repeated_value", "Tuple(Int32, String)",
    ).should be_nil
  end

  it "preserves ordinary input bindings and rejects a conflicting callback result" do
    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "prebound", "Array(Int32)", {"T" => "Int32"},
    ).should eq({"T" => "Int32"})

    converter = source_block_generic_return_binding_fixture
    converter.__test_source_block_output_type_bindings(
      "SourceBlockGenericReturnBindingProbe", "prebound", "Array(String)", {"T" => "Int32"},
    ).should be_nil
  end
end
