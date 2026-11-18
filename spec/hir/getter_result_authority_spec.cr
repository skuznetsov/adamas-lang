require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_result_before_body(symbol : String, arity : Int32) : Adamas::HIR::TypeRef
    get_function_return_type(symbol, arity)
  end
end

private def register_result_authority_fixture
  source = <<-CRYSTAL
    class ColdResult
      @payload : Char
      @secret : Char
      getter mark : Char
      getter? ready : Bool

      def initialize(@payload : Char, @secret : Char, @mark : Char, @ready : Bool)
      end

      def payload
        @payload.ord
      end

      def payload(input)
        value = self.payload
        return if input < 0
        value
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  converter.register_class(arena[program.roots.first].as(Adamas::Compiler::Frontend::ClassNode))
  converter
end

describe "return facts of unmaterialized methods" do
  it "waits for the selected specialization when its namesake field has a different type" do
    converter = register_result_authority_fixture
    result = converter.__test_result_before_body("ColdResult#payload$Int32", 1)
    unless result == Adamas::HIR::TypeRef::VOID
      inferred = converter.module.get_type_descriptor(result).not_nil!
      inferred.kind.should eq(Adamas::HIR::TypeKind::Union)
      inferred.type_params.map(&.id).sort.should eq([Adamas::HIR::TypeRef::NIL.id, Adamas::HIR::TypeRef::INT32.id].sort)
    end
  end

  it "does not infer a method from a field without a getter" do
    converter = register_result_authority_fixture
    converter.__test_result_before_body("ColdResult#secret", 0).should eq(Adamas::HIR::TypeRef::VOID)
    converter.__test_result_before_body("ColdResult#secret$Int32", 1).should eq(Adamas::HIR::TypeRef::VOID)
  end

  it "uses the registered getter and predicate getter contracts" do
    converter = register_result_authority_fixture
    converter.__test_result_before_body("ColdResult#mark", 0).should eq(Adamas::HIR::TypeRef::CHAR)
    converter.__test_result_before_body("ColdResult#ready?", 0).should eq(Adamas::HIR::TypeRef::BOOL)
  end
end
