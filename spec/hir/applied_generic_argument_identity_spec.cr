require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_applied_parameter_source_mismatch(definition, actual : String, owner : String)
    actual_type = canonical_bound_type_ref(actual)
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = owner
    @current_namespace_override = "Scope"
    begin
      source_generic_argument_mismatch_for_def(definition, [actual_type], owner)
    ensure
      @current_class = old_class
      @current_namespace_override = old_namespace
    end
  end

  def __test_applied_parameter_identity(definition, actual : String, owner : String)
    actual_type = canonical_bound_type_ref(actual)
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = owner
    @current_namespace_override = "Scope"
    begin
      params_compatible_with_args?(definition, [actual_type], owner)
    ensure
      @current_class = old_class
      @current_namespace_override = old_namespace
    end
  end
end

private def collect_applied_identity_definitions(arena, expression, definitions)
  case node = arena[expression]
  when Adamas::Compiler::Frontend::DefNode
    definitions[String.new(node.name)] = node
  when Adamas::Compiler::Frontend::ClassNode, Adamas::Compiler::Frontend::ModuleNode
    node.body.try &.each { |child| collect_applied_identity_definitions(arena, child, definitions) }
  end
end

private def applied_parameter_identity_fixture
  source = <<-CRYSTAL
    class Path
    end
    module Scope
      class Path
      end
      class Box(T)
        def nullable(value : T?); end
        def direct(value : T); end
        def union(value : T | String); end
        def numeric_union(value : T | Int); end
        def array(value : Array(T)?); end
        def pointer(value : Pointer(T)); end
        def lexical(value : Path); end
        def rest(*values : T?); end
        def rest_numeric(*values : T | Int); end
        def rest_plain_numeric(*values : Int); end
      end
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena)
  converter.seed_top_level_type_names(["Path", "Scope"])
  definitions = {} of String => Adamas::Compiler::Frontend::DefNode
  program.roots.each do |expression|
    case node = program.arena[expression]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
    collect_applied_identity_definitions(program.arena, expression, definitions)
  end
  {converter, definitions}
end

describe "applied generic parameter identity" do
  it "keeps a composite owner's resolved arguments at the source rejection fence" do
    converter, definitions = applied_parameter_identity_fixture
    converter.__test_applied_parameter_identity(definitions["nullable"], "Array(Path)", "Scope::Box(Array(Path))").should be_true
    converter.__test_applied_parameter_source_mismatch(definitions["nullable"], "Array(Path)", "Scope::Box(Array(Path))").should be_nil
  end

  it "rejects a different composite argument at the source rejection fence" do
    converter, definitions = applied_parameter_identity_fixture
    converter.__test_applied_parameter_identity(definitions["nullable"], "Array(Scope::Path)", "Scope::Box(Array(Path))").should be_false
    converter.__test_applied_parameter_source_mismatch(definitions["nullable"], "Array(Scope::Path)", "Scope::Box(Array(Path))").should_not be_nil
  end

  {
    {"nullable", "Path", true},
    {"nullable", "Nil", true},
    {"nullable", "Scope::Path", false},
    {"direct", "Path", true},
    {"direct", "Scope::Path", false},
    {"union", "Path", true},
    {"union", "String", true},
    {"union", "Scope::Path", false},
    {"numeric_union", "UInt64", true},
    {"numeric_union", "Float64", false},
    {"numeric_union", "Path", true},
    {"array", "Array(Path)", true},
    {"array", "Nil", true},
    {"array", "Array(Scope::Path)", false},
    {"pointer", "Pointer(Path)", true},
    {"pointer", "Pointer(Scope::Path)", false},
    {"lexical", "Scope::Path", true},
    {"lexical", "Path", false},
    {"rest", "Path", true},
    {"rest", "Nil", true},
    {"rest", "Scope::Path", false},
    {"rest_numeric", "UInt64", true},
    {"rest_numeric", "Float64", false},
    {"rest_numeric", "Path", true},
    {"rest_plain_numeric", "UInt64", true},
    {"rest_plain_numeric", "Float64", false},
    {"rest_plain_numeric", "Path", false},
  }.each do |method, actual, expected|
    it "#{expected ? "admits" : "rejects"} #{actual} for #{method} in a colliding lexical namespace" do
      converter, definitions = applied_parameter_identity_fixture
      converter.__test_applied_parameter_identity(definitions[method], actual, "Scope::Box(Path)").should eq(expected)
    end
  end
end
