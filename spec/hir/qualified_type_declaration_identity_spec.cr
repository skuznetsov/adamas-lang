require "spec"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"

class Adamas::HIR::AstToHir
  def __test_qualified_enum_base(name : String) : TypeRef
    enum_base_type(name)
  end

  def __test_qualified_enum_names : Array(String)
    @enum_info.try(&.keys) || [] of String
  end

  def __test_qualified_enum_members(name : String) : Hash(String, Int64)
    @enum_info.not_nil![name]
  end

  def __test_declaration_namespace_exists(name : String) : Bool
    @module_defs.has_key?(name)
  end

  def __test_declaration_namespace_published(name : String) : Bool
    @published_source_module_names.includes?(name)
  end

  def __test_retained_module_count(name : String) : Int32
    @module_defs[name]?.try(&.size) || 0
  end

  def __test_prescan_qualified_module(source : String) : Nil
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    old_arena = @arena
    @arena = program.arena
    begin
      pre_register_module_scoped_macros(program.arena[program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode))
    ensure
      @arena = old_arena
    end
  end

  def __test_register_generated_enum(source : String) : Nil
    generated_id = macro_expander_for_current_context.reparse_output(source, ExprId.new(0))
    node = @arena[generated_id]
    if node.is_a?(Adamas::Compiler::Frontend::BeginNode)
      generated_id = node.body.last
      node = @arena[generated_id]
    end
    enum_node = node.as(Adamas::Compiler::Frontend::EnumNode)
    register_enum_with_name(enum_node, String.new(enum_node.name), generated_id)
  end

  def __test_prescan_qualified_enum(source : String) : Nil
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    old_arena = @arena
    @arena = program.arena
    begin
      pre_register_enum_scoped_macros(program.arena[program.roots.first].as(Adamas::Compiler::Frontend::EnumNode))
    ensure
      @arena = old_arena
    end
  end

  def __test_source_declaration_name(owner : String?, name : String) : String
    qualified_source_declaration_name(owner, name)
  end
end

private def qualified_declaration_converter(source : String, prescan : Bool = false)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  if prescan
    classes = program.roots.compact_map do |id|
      node = program.arena[id]
      {String.new(node.name), node.is_struct == true} if node.is_a?(Adamas::Compiler::Frontend::ClassNode)
    end
    converter.seed_top_level_type_names(classes.map(&.[0]))
    converter.seed_top_level_class_kinds(classes)
    program.roots.each do |id|
      node = program.arena[id]
      converter.pre_register_module_scoped_macros(node) if node.is_a?(Adamas::Compiler::Frontend::ModuleNode)
    end
  end
  program.roots.each do |id|
    case node = program.arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::EnumNode
      converter.register_enum(node)
    when Adamas::Compiler::Frontend::AliasNode
      converter.register_alias(node)
    end
  end
  converter
end

describe "qualified enum declaration identities" do
  it "publishes complete qualified names with AST-owned and default base types" do
    converter = qualified_declaration_converter(<<-CR)
      module QualifiedEnumOwner
      end
      enum QualifiedEnumOwner::ByteLevel : UInt8
        Active = 65
      end
      enum ::QualifiedEnumOwner::DefaultLevel
        Active
      end
    CR
    converter.__test_qualified_enum_names.sort.should eq([
      "QualifiedEnumOwner::ByteLevel", "QualifiedEnumOwner::DefaultLevel",
    ])
    converter.__test_qualified_enum_base("QualifiedEnumOwner::ByteLevel").should eq(Adamas::HIR::TypeRef::UINT8)
    converter.__test_qualified_enum_base("QualifiedEnumOwner::DefaultLevel").should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "keeps rooted names outside nested module and class registration contexts" do
    converter = qualified_declaration_converter(<<-CR)
      module QualifiedEnumScope
        enum ::QualifiedRootLevel : UInt8
          Active
        end
        enum Child::LocalLevel : UInt8
          Active
        end
      end
      class QualifiedEnumClass
        enum ::QualifiedRootClassLevel : UInt8
          Active
        end
      end
    CR
    converter.__test_qualified_enum_names.sort.should eq([
      "QualifiedEnumScope::Child::LocalLevel", "QualifiedRootClassLevel", "QualifiedRootLevel",
    ])
  end

  it "probes a complete namespace prefix before restarting missing-module creation" do
    converter = qualified_declaration_converter(<<-CR)
      module QualifiedOuter
        module Inner
        end
      end
    CR
    converter.__test_source_declaration_name("QualifiedOuter::Inner", "Inner::Level")
      .should eq("QualifiedOuter::Inner::Level")
    converter.__test_source_declaration_name("QualifiedOuter::Inner", "QualifiedOuter::Inner::Level")
      .should eq("QualifiedOuter::Inner::QualifiedOuter::Inner::Level")
    converter.__test_source_declaration_name("QualifiedOuter::Inner", "::QualifiedOuter::RootLevel")
      .should eq("QualifiedOuter::RootLevel")
  end

  it "uses each generated enum's retained source for names, values, and flags" do
    converter = qualified_declaration_converter(<<-CR)
      module QualifiedGeneratedOwner
      end
      class QualifiedMacroClass
        {% if true %}
          enum ::QualifiedGeneratedOwner::First : UInt8
            Active = 75
          end
        {% end %}
        {% if true %}
          @[Flags]
          enum ::QualifiedGeneratedOwner::Second : UInt8
            First
            Second
            Eight = 8
            Next
          end
        {% end %}
      end
    CR
    converter.__test_qualified_enum_members("QualifiedGeneratedOwner::First")
      .should eq({"Active" => 75_i64})
    converter.__test_qualified_enum_members("QualifiedGeneratedOwner::Second")
      .should eq({"First" => 1_i64, "Second" => 2_i64, "Eight" => 8_i64, "Next" => 16_i64})
  end


  it "publishes the missing modules created by a qualified declaration" do
    converter = qualified_declaration_converter(<<-CR)
      enum QualifiedImplicitOwner::Nested::Level
        Active
      end
    CR
    converter.__test_declaration_namespace_exists("QualifiedImplicitOwner").should be_true
    converter.__test_declaration_namespace_exists("QualifiedImplicitOwner::Nested").should be_true
  end

  it "does not publish qualified namespace components during enum macro prescan" do
    converter = qualified_declaration_converter("nil")
    converter.__test_prescan_qualified_enum("enum QualifiedPrescanOwner::Nested::Level\nActive\nend")
    converter.__test_declaration_namespace_exists("QualifiedPrescanOwner").should be_false
    converter.__test_declaration_namespace_exists("QualifiedPrescanOwner::Nested").should be_false
    converter.__test_qualified_enum_names.should be_empty
  end

  it "keeps retained module AST separate from source namespace publication" do
    converter = qualified_declaration_converter("nil")
    converter.__test_prescan_qualified_module("module QualifiedRetainedOwner\nend")
    converter.__test_declaration_namespace_exists("QualifiedRetainedOwner").should be_true
    converter.__test_declaration_namespace_published("QualifiedRetainedOwner").should be_false
    converter.__test_source_declaration_name(nil, "QualifiedRetainedOwner::Level")
    converter.__test_declaration_namespace_published("QualifiedRetainedOwner").should be_true
    converter.__test_retained_module_count("QualifiedRetainedOwner").should eq(1)
  end

  it "retains module kind after an implicit namespace acquires an explicit reopening" do
    ["enum QualifiedReopenedOwner\nActive\nend", "alias QualifiedReopenedOwner = Int32"].each do |replacement|
      expect_raises(Adamas::HIR::LoweringError, "already defined as a module") do
        qualified_declaration_converter(<<-CR, prescan: true)
          enum QualifiedReopenedOwner::Level
            Active
          end
          module QualifiedReopenedOwner
          end
          #{replacement}
        CR
      end
    end
  end

  it "rejects enum/module and module/class collisions despite complete future inventories" do
    [
      "enum QualifiedKindOwner\nActive\nend\nmodule QualifiedKindOwner\nend",
      "module QualifiedKindOwner\nend\nclass QualifiedKindOwner\nend",
      "class QualifiedKindOwner\nend\nmodule QualifiedKindOwner\nend",
      "module Regex\nend",
      "module QualifiedOuter\nmodule Kind\nend\nclass Kind\nend\nend",
      "module QualifiedOuter\nclass Kind\nend\nmodule Kind\nend\nend",
      "class QualifiedOuter\nmodule Kind\nend\nclass Kind\nend\nend",
      "class QualifiedOuter\nclass Kind\nend\nmodule Kind\nend\nend",
    ].each do |source|
      expect_raises(Adamas::HIR::LoweringError, "already defined") do
        qualified_declaration_converter(source, prescan: true)
      end
    end
  end

  it "lets path wrappers traverse published classes while the actual leaf keeps module kind" do
    qualified_declaration_converter(<<-CR, prescan: true)
      class QualifiedWrapperOwner
        class Nested
        end
      end
      class QualifiedWrapperOwner::Child
      end
      module QualifiedWrapperOwner::Members
      end
      module QualifiedWrapperOwner::Nested::Members
      end
    CR
  end

  it "reopens an aliased module under its selected target identity" do
    converter = qualified_declaration_converter(<<-CR, prescan: true)
      module QualifiedActualModule
      end
      alias QualifiedModuleAlias = QualifiedActualModule
      module QualifiedModuleAlias
        enum Level
          Active
        end
      end
    CR
    converter.__test_qualified_enum_names.should eq(["QualifiedActualModule::Level"])
    converter.__test_declaration_namespace_published("QualifiedModuleAlias").should be_false
    converter.__test_declaration_namespace_published("QualifiedActualModule").should be_true
  end

  it "rejects module declarations over non-module aliases before publishing a namespace" do
    ["Int32 | String", "Void", "Int32", "Pointer(Int32)"].each do |target|
      expect_raises(Adamas::HIR::LoweringError) do
        qualified_declaration_converter("alias QualifiedNonModuleAlias = #{target}\nmodule QualifiedNonModuleAlias\nend", prescan: true)
      end
    end
  end

  it "leaves prefix validation to source registration rather than macro prescan" do
    converter = qualified_declaration_converter("enum QualifiedPrescanEnum\nActive\nend")
    converter.__test_prescan_qualified_enum("enum QualifiedPrescanEnum::Nested\nActive\nend")
    converter.__test_qualified_enum_names.should eq(["QualifiedPrescanEnum"])
  end

  it "rejects replacing an implicit module with another declaration kind" do
    [
      "enum QualifiedCollisionOwner\nActive\nend",
      "class QualifiedCollisionOwner\nend",
      "struct QualifiedCollisionOwner\nend",
      "alias QualifiedCollisionOwner = Int32",
    ].each do |declaration|
      expect_raises(Adamas::HIR::LoweringError, "already defined as a module") do
        qualified_declaration_converter("enum QualifiedCollisionOwner::Level\nActive\nend\n#{declaration}")
      end
    end
  end

  it "does not treat future class name inventory as source publication" do
    source = <<-CR
      enum QualifiedFutureOwner::Nested
        Active
      end
      class QualifiedFutureOwner
      end
    CR
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    converter = Adamas::HIR::AstToHir.new(program.arena,
      sources_by_arena: {program.arena.object_id.to_u64 => source})
    converter.seed_top_level_type_names(["QualifiedFutureOwner"])
    converter.seed_top_level_class_kinds([{"QualifiedFutureOwner", false}])
    converter.register_enum(program.arena[program.roots.first].as(Adamas::Compiler::Frontend::EnumNode))
    converter.__test_declaration_namespace_exists("QualifiedFutureOwner").should be_true
    expect_raises(Adamas::HIR::LoweringError, "already defined as a module") do
      converter.register_class(program.arena[program.roots.last].as(Adamas::Compiler::Frontend::ClassNode))
    end
  end

  it "uses predefined source namespaces before their source class reopening" do
    converter = qualified_declaration_converter("nil")
    ["Object", "Reference", "Value", "Struct", "Number", "Int", "Float", "Enum",
     "Regex", "Exception", "Class", "Enumerable", "Indexable", "Union", "GC", "Crystal"].each do |name|
      converter.__test_source_declaration_name(nil, "#{name}::Level").should eq("#{name}::Level")
      converter.__test_declaration_namespace_exists(name).should be_false
    end
    qualified_declaration_converter("enum Regex::QualifiedLevel\nActive\nend\nclass Regex\nend")
    qualified_declaration_converter("enum Exception::QualifiedLevel\nActive\nend\nclass Exception\nend")
  end

  it "does not let backend generic shortcuts invent source declarations" do
    ["Set", "Iterator"].each do |name|
      expect_raises(Adamas::HIR::LoweringError, "already defined as a module") do
        qualified_declaration_converter("enum #{name}::QualifiedLevel\nActive\nend\nclass #{name}(T)\nend")
      end
    end
  end

  it "rejects an enum prefix instead of treating it as a missing namespace" do
    expect_raises(Adamas::HIR::LoweringError, "can't declare type inside enum QualifiedInvalidEnumPrefix") do
      qualified_declaration_converter(<<-CR)
        enum QualifiedInvalidEnumPrefix
          Active
        end
        alias QualifiedInvalidEnumPrefix::Nested = Int32
      CR
    end
  end

  it "rejects aliases to compound types as qualified declaration namespaces" do
    [
      "alias QualifiedUnionPrefix = Int32 | String\nalias QualifiedUnionPrefix::Nested = Int32",
      "alias QualifiedProcPrefix = Proc(Int32, Nil)\nalias QualifiedProcPrefix::Nested = Int32",
      "alias QualifiedTuplePrefix = Tuple(Int32)\nalias QualifiedTuplePrefix::Nested = Int32",
      "alias QualifiedPointerPrefix = Pointer(Int32)\nalias QualifiedPointerPrefix::Nested = Int32",
      "alias QualifiedStaticArrayPrefix = StaticArray(Int32, 1)\nalias QualifiedStaticArrayPrefix::Nested = Int32",
    ].each do |source|
      expect_raises(Adamas::HIR::LoweringError) do
        qualified_declaration_converter(source)
      end
    end
  end

  it "rejects an applied user generic instance as a declaration namespace" do
    source = <<-CR
      class QualifiedNamespaceBox(T)
      end
      alias QualifiedGenericPrefix = QualifiedNamespaceBox(Int32)
      alias QualifiedGenericPrefix::Nested = Int32
    CR
    expect_raises(Adamas::HIR::LoweringError) do
      qualified_declaration_converter(source)
    end
  end

  it "keeps registered primitive classes usable as declaration namespaces" do
    converter = qualified_declaration_converter(<<-CR)
      alias QualifiedPrimitivePrefix = Int32
      alias QualifiedPrimitivePrefix::Nested = UInt8
    CR
    converter.__test_source_declaration_name(nil, "QualifiedPrimitivePrefix::Nested")
      .should eq("Int32::Nested")
  end


  it "keeps generated ownership when spans exceed the primary source buffer" do
    converter = qualified_declaration_converter("nil")
    converter.__test_register_generated_enum(<<-CR)
      @[Flags]
      enum QualifiedWideGenerated : UInt8
        First
        Second
        Eight = 8
        Next
      end
    CR
    converter.__test_qualified_enum_members("QualifiedWideGenerated")
      .should eq({"First" => 1_i64, "Second" => 2_i64, "Eight" => 8_i64, "Next" => 16_i64})
  end

end
