require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_type_ref_for_name(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  # Test-only access to the conversion signature table.  Keep production
  # visibility narrow: the actual call fallback remains receiver-gated.
  def __test_conversion_method_return_type(name : String) : Adamas::HIR::TypeRef?
    conversion_method_return_type(name)
  end
end

private def parse_conversion_source(source : String)
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  program = parser.parse_program
  {parser.arena, program.roots}
end

private def lower_conversion_function(source : String, name : String) : {Adamas::HIR::AstToHir, Adamas::HIR::Function}
  arena, roots = parse_conversion_source(source)
  converter = Adamas::HIR::AstToHir.new(arena)
  defs = roots.compact_map do |root_id|
    node = arena[root_id]
    node.as?(Adamas::Compiler::Frontend::DefNode)
  end
  defs.each { |node| converter.register_function(node) }
  def_node = defs.find { |node| (String.new(node.name) == name) }
  raise "missing test function #{name}" unless def_node
  {converter, converter.lower_def(def_node.not_nil!)}
end

private def lower_conversion_program(source : String) : {Adamas::HIR::AstToHir, Array(Adamas::HIR::Function)}
  arena, roots = parse_conversion_source(source)
  converter = Adamas::HIR::AstToHir.new(arena)
  classes = roots.compact_map do |root_id|
    arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
  end
  defs = roots.compact_map do |root_id|
    arena[root_id].as?(Adamas::Compiler::Frontend::DefNode)
  end
  classes.each { |node| converter.register_class(node) }
  defs.each { |node| converter.register_function(node) }
  classes.each { |node| converter.lower_class(node) }
  functions = defs.map { |node| converter.lower_def(node) }
  {converter, functions}
end

private def function_value_types(function : Adamas::HIR::Function) : Hash(Adamas::HIR::ValueId, Adamas::HIR::TypeRef)
  types = {} of Adamas::HIR::ValueId => Adamas::HIR::TypeRef
  function.params.each { |param| types[param.id] = param.type }
  function.blocks.each do |block|
    block.instructions.each { |instruction| types[instruction.id] = instruction.type }
  end
  types
end

describe "nilable numeric conversion typing" do
  it "maps question-mark aliases to Nil-or-primitive types" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    int32_nullable = converter.__test_type_ref_for_name("Int32?")
    converter.__test_conversion_method_return_type("to_i?").should eq(int32_nullable)
    converter.__test_conversion_method_return_type("to_i32?").should eq(int32_nullable)
    converter.__test_conversion_method_return_type("to_i").should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_conversion_method_return_type("to_i32!").should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "keeps a String#to_i? call nullable and narrows a guarded array index" do
    converter, function = lower_conversion_function(<<-CRYSTAL, "parse_index")
      def parse_index(text : String)
        values = [10, 20]
        index = text.to_i?
        return 0 unless index
        values[index]
      end
    CRYSTAL

    int32_nullable = converter.__test_type_ref_for_name("Int32?")
    conversion = function.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call)
    end.find { |call| call.method_name.ends_with?("String#to_i?") }
    conversion.should_not be_nil
    conversion.not_nil!.type.should eq(int32_nullable)

    types = function_value_types(function)
    index_get = function.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::IndexGet)
    end.first
    index_get.should_not be_nil
    types[index_get.not_nil!.index].should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "does not override a user-defined to_i? on a non-builtin receiver" do
    converter, functions = lower_conversion_program(<<-CRYSTAL)
      class FakeNumber
        def to_i?
          "custom"
        end
      end

      def use_fake(value : FakeNumber)
        value.to_i?
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.starts_with?("use_fake") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call)
    end.find { |candidate| candidate.method_name.includes?("FakeNumber#to_i?") }
    call.should_not be_nil
    call.not_nil!.type.should eq(Adamas::HIR::TypeRef::STRING)
    converter.__test_conversion_method_return_type("to_i?").should_not eq(Adamas::HIR::TypeRef::STRING)
  end
end
