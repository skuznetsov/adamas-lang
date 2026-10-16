require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_registered_scalar_disjoint(name : String, target : Adamas::HIR::TypeRef) : Bool?
    statically_is_a_type?(@class_info[name].type_ref, target)
  end
end

private def registered_scalar_converter(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  defs = [] of Adamas::Compiler::Frontend::DefNode
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
      defs << node
    end
  end
  defs.each { |node| converter.lower_def(node) }
  converter
end

describe "Registered source carriers against concrete scalar builtins" do
  it "proves registered classes and structs disjoint from scalar builtins" do
    converter = registered_scalar_converter("class ScalarCaseClass; end\nstruct ScalarCaseStruct; end\n")
    ["ScalarCaseClass", "ScalarCaseStruct"].each do |name|
      [Adamas::HIR::TypeRef::BOOL, Adamas::HIR::TypeRef::UINT8,
       Adamas::HIR::TypeRef::INT64, Adamas::HIR::TypeRef::FLOAT64,
       Adamas::HIR::TypeRef::CHAR, Adamas::HIR::TypeRef::SYMBOL].each do |target|
        converter.__test_registered_scalar_disjoint(name, target).should eq(false)
      end
    end
  end

  it "preserves predefined ancestor carriers without a loaded builtin declaration" do
    converter = registered_scalar_converter(<<-CRYSTAL)
      abstract class Object; end
      abstract class Reference < Object; end
      abstract struct Value; end
      abstract struct Number < Value; end
      abstract struct Int < Number; end
      abstract struct Float < Number; end
    CRYSTAL
    ["Object", "Value", "Number", "Int"].each do |name|
      converter.__test_registered_scalar_disjoint(name, Adamas::HIR::TypeRef::UINT8).should be_nil
    end
    ["Object", "Value", "Number", "Float"].each do |name|
      converter.__test_registered_scalar_disjoint(name, Adamas::HIR::TypeRef::FLOAT64).should be_nil
    end
    converter.__test_registered_scalar_disjoint("Reference", Adamas::HIR::TypeRef::UINT8).should eq(false)
    converter.__test_registered_scalar_disjoint("Number", Adamas::HIR::TypeRef::BOOL).should eq(false)
  end

  it "keeps String and erased Pointer targets outside the scalar proof" do
    converter = registered_scalar_converter("class ScalarCaseClass; end\nstruct ScalarCaseStruct; end\n")
    ["ScalarCaseClass", "ScalarCaseStruct"].each do |name|
      converter.__test_registered_scalar_disjoint(name, Adamas::HIR::TypeRef::STRING).should be_nil
      converter.__test_registered_scalar_disjoint(name, Adamas::HIR::TypeRef::POINTER).should be_nil
      converter.__test_registered_scalar_disjoint(name, Adamas::HIR::TypeRef::VOID).should be_nil
    end
  end

  it "does not lower a scalar branch disjoint from every union member" do
    converter = registered_scalar_converter(<<-CRYSTAL)
      struct UInt8; end
      struct ScalarCasePayload; end
      def scalar_case_probe(value : ScalarCasePayload | Bool)
        case value
        when UInt8
          9101
        else
          42
        end
      end
    CRYSTAL
    function = converter.module.functions.find { |item| item.name.starts_with?("scalar_case_probe") }.not_nil!
    instructions = function.blocks.flat_map(&.instructions)
    instructions.select(Adamas::HIR::Literal)
      .none? { |value| value.type == Adamas::HIR::TypeRef::INT32 && value.int_value == 9101 }.should be_true
  end

  it "retains a scalar branch when a union member can match" do
    converter = registered_scalar_converter(<<-CRYSTAL)
      struct UInt8; end
      struct ScalarCasePayload; end
      def scalar_case_probe(value : ScalarCasePayload | UInt8)
        case value
        when UInt8
          9201
        else
          42
        end
      end
    CRYSTAL
    function = converter.module.functions.find { |item| item.name.starts_with?("scalar_case_probe") }.not_nil!
    function.blocks.flat_map(&.instructions).select(Adamas::HIR::Literal)
      .any? { |value| value.type == Adamas::HIR::TypeRef::INT32 && value.int_value == 9201 }.should be_true
  end
end
