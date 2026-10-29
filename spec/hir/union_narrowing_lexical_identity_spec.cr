require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_union_narrowing_identity(
    context : String?,
    namespace : String?,
    bindings : Hash(String, String) = {} of String => String,
  ) : {Adamas::HIR::TypeRef, Adamas::HIR::TypeRef?, Array(String)}
    expected = type_ref_for_name("Path | String")
    source = type_ref_for_name("Nil | Path | String")
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = context
    @current_namespace_override = namespace
    begin
      with_type_param_map(bindings) do
        narrowed = non_nil_type_for_union(source)
        names = narrowed.try { |ref| union_descriptor_from_sidecar(ref).try(&.variants.map(&.full_name)) } || [] of String
        {expected, narrowed, names}
      end
    ensure
      @current_class = old_class
      @current_namespace_override = old_namespace
    end
  end
end

private def lexical_union_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class Path
    end
    module Scope
      class Path
      end
      class Caller
      end
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  parsed.roots.each do |expr|
    case node = parsed.arena[expr]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end
  converter
end

describe "resolved union narrowing identity" do
  it "retains resolved arms when the consumer has a same-named nested type" do
    expected, actual, names = lexical_union_converter.__test_union_narrowing_identity("Scope::Caller", nil)
    actual.should eq(expected)
    names.should eq(["Path", "String"])
  end

  it "retains resolved arms under an included-module namespace override" do
    expected, actual, names = lexical_union_converter.__test_union_narrowing_identity("Scope::Caller", "Scope")
    actual.should eq(expected)
    names.should eq(["Path", "String"])
  end

  it "does not substitute an already-resolved nominal arm through a caller binding" do
    expected, actual, names = lexical_union_converter.__test_union_narrowing_identity(nil, nil, {"Path" => "Int32"})
    actual.should eq(expected)
    names.should eq(["Path", "String"])
  end
end
