require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_initializer_source_functions : Array(Adamas::HIR::Function)
    @materialized_initializer_sources.values.map(&.function)
  end

  def __test_initializer_source_current?(name : String) : Bool
    materialized_initializer_source_current?(@materialized_initializer_sources[name])
  end

  def __test_initializer_origin_name(name : String) : String
    @materialized_initializer_sources[name].source_name
  end

  def __test_initializer_has_source_overload?(name : String) : Bool
    @function_defs.has_key?(name)
  end

  def __test_forget_initializer_origin(name : String) : Nil
    source = @materialized_initializer_sources[name]
    @function_def_arenas.delete(source.source_name)
  end
end

private def lower_initializer_origin_fixture : Adamas::HIR::AstToHir
  code = <<-CRYSTAL
    class InitializerOrigin
      def initialize(value : Int, offset : Int32 = 3)
      end
    end
    InitializerOrigin.new(2)
  CRYSTAL
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  main = [] of UInt64
  result.roots.each do |id|
    case node = result.arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      converter.lower_class(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter.__test_initializer_source_functions.should_not be_empty
  converter
end

describe "materialized initializer source identity" do
  it "retains the registered source identity of a completed initializer" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    source_name = converter.__test_initializer_origin_name(function.name)
    converter.__test_initializer_has_source_overload?(source_name).should be_true
    converter.__test_initializer_source_current?(function.name).should be_true
  end

  it "rejects an initializer whose return ABI changes after lowering" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    converter.__test_initializer_source_current?(function.name).should be_true
    function.return_type = Adamas::HIR::TypeRef::INT64
    converter.__test_initializer_source_current?(function.name).should be_false
  end

  it "rejects an initializer whose source arena is no longer registered" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    converter.__test_initializer_source_current?(function.name).should be_true
    converter.__test_forget_initializer_origin(function.name)
    converter.__test_initializer_source_current?(function.name).should be_false
  end
end
