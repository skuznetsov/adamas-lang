require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_enum_nominal_type_ref_for_enum_module_suffix(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __test_enum_nominal_enum_owner_for_type(type_ref : Adamas::HIR::TypeRef) : String?
    enum_name_for_type_ref(type_ref)
  end

  def __test_enum_nominal_module_like_name?(name : String) : Bool
    module_like_type_name?(name)
  end

  def __test_enum_nominal_module_type_ref?(type_ref : Adamas::HIR::TypeRef) : Bool
    module_type_ref?(type_ref)
  end

  def __test_enum_nominal_function_def_for_name(name : String) : Adamas::HIR::Function?
    @module.functions.find { |function| function.name.starts_with?(name) }
  end
end

private def lower_enum_nominal_fixture : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    module EnumDomain
      @[Flags]
      enum Options : UInt32
        One = 1
      end
    end

    module OtherDomain
      enum Options : UInt32
        Two = 2
      end
    end

    module Collision
      module Options
        def probe : Int32
          73
        end
      end

      class Config
        include Options
      end
    end

    alias OptionsAlias = EnumDomain::Options

    def enum_alias_probe(value : OptionsAlias) : UInt64
      value.hash
    end

    def module_typed_probe(value : Collision::Options) : Int32
      value.probe
    end

    def enum_typed_probe(value : EnumDomain::Options) : UInt64
      value.hash
    end

    def enum_explicit_call_probe(value : EnumDomain::Options) : UInt64
      value.hash()
    end

    def enum_other_owner_probe(value : OtherDomain::Options) : UInt64
      value.hash
    end

    def integer_probe(value : UInt32) : UInt64
      value.hash
    end

    def enum_underlying_probe(value : EnumDomain::Options) : UInt64
      value.value.hash
    end

    def unknown_probe(value : Object) : UInt64
      value.hash
    end

    def module_explicit_probe(value : Collision::Options) : Int32
      value.probe()
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena, sources_by_arena: {arena.object_id.to_u64 => source}
  )
  converter.arena = arena
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::EnumNode
      converter.register_enum(node)
    when Adamas::Compiler::Frontend::AliasNode
      converter.register_alias(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    end
  end
  program.roots.each do |root_id|
    node = arena[root_id]
    converter.lower_def(node) if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  converter
end

describe "nominal enum identity before module suffix lookup" do
  it "uses canonical enum identity from the value through member and explicit call lowering" do
    converter = lower_enum_nominal_fixture
    enum_type = converter.__test_enum_nominal_type_ref_for_enum_module_suffix("EnumDomain::Options")
    alias_type = converter.__test_enum_nominal_type_ref_for_enum_module_suffix("OptionsAlias")

    converter.__test_enum_nominal_enum_owner_for_type(enum_type).should eq("EnumDomain::Options")
    converter.__test_enum_nominal_enum_owner_for_type(alias_type).should eq("EnumDomain::Options")
    converter.__test_enum_nominal_module_like_name?("EnumDomain::Options").should be_false

    {"enum_typed_probe", "enum_alias_probe", "enum_explicit_call_probe"}.each do |function_name|
      function = converter.__test_enum_nominal_function_def_for_name(function_name)
      function.should_not be_nil

      call = function.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
        .find { |candidate| candidate.method_name.includes?("#hash") }
      call.should_not be_nil
      call.not_nil!.method_name.should contain("EnumDomain::Options#hash")
      call.not_nil!.method_name.should_not contain("Collision::Options")
    end
  end

  it "does not transfer enum identity to another enum owner, integers, or unknown values" do
    converter = lower_enum_nominal_fixture
    {"enum_other_owner_probe" => "OtherDomain::Options", "integer_probe" => "UInt32"}.each do |function_name, owner|
      function = converter.__test_enum_nominal_function_def_for_name(function_name)
      function.should_not be_nil

      call = function.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
        .find { |candidate| candidate.method_name.includes?("#hash") }
      call.should_not be_nil
      call.not_nil!.method_name.should contain("#{owner}#hash")
      call.not_nil!.method_name.should_not contain("EnumDomain::Options")
      call.not_nil!.method_name.should_not contain("Collision::Options")
    end

    unknown = converter.__test_enum_nominal_function_def_for_name("unknown_probe")
    unknown.should_not be_nil
    unknown_calls = unknown.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
    unknown_call = unknown_calls.find { |candidate| candidate.method_name.includes?("#hash") }
    unknown_call.should_not be_nil
    unknown_call.not_nil!.method_name.should_not contain("Collision::Options")
    unknown_call.not_nil!.method_name.should_not contain("EnumDomain::Options")
  end

  it "keeps real module dispatch through both member access and an explicit call" do
    converter = lower_enum_nominal_fixture
    {"module_typed_probe", "module_explicit_probe"}.each do |function_name|
      function = converter.__test_enum_nominal_function_def_for_name(function_name)
      function.should_not be_nil

      call = function.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
        .find { |candidate| candidate.method_name.includes?("#probe") }
      call.should_not be_nil
      call.not_nil!.method_name.should contain("Collision::Config#probe")
    end
  end

  it "keeps an exact registered enum distinct from same-suffix modules" do
    converter = lower_enum_nominal_fixture
    enum_type = converter.__test_enum_nominal_type_ref_for_enum_module_suffix("EnumDomain::Options")
    converter.__test_enum_nominal_enum_owner_for_type(enum_type).should eq("EnumDomain::Options")
    converter.__test_enum_nominal_module_type_ref?(enum_type).should be_false
    module_type = converter.__test_enum_nominal_type_ref_for_enum_module_suffix("Collision::Options")
    converter.__test_enum_nominal_module_type_ref?(module_type).should be_true
  end

  it "drops enum dispatch after an explicit conversion to the underlying integer" do
    converter = lower_enum_nominal_fixture
    function = converter.__test_enum_nominal_function_def_for_name("enum_underlying_probe")
    function.should_not be_nil

    call = function.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .find { |candidate| candidate.method_name.includes?("#hash") }
    call.should_not be_nil
    call.not_nil!.method_name.should contain("UInt32#hash")
    call.not_nil!.method_name.should_not contain("Options#hash")
  end
end
