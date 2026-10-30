require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_extern_source_result(expr : Adamas::Compiler::Frontend::ExprId, owner : String? = nil) : String?
    previous_owner = @current_class
    @current_class = owner if owner
    infer_type_from_expr(expr, owner).try { |type| get_type_name_from_ref(type) }
  ensure
    @current_class = previous_owner
  end
end

private def registered_extern_source_probe(declarations : String, expression : String)
  source = declarations + "\n" + expression
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?
  converter = Adamas::HIR::AstToHir.new(
    parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source},
  )
  parsed.roots.each do |root|
    case node = parsed.arena[root]
    when Adamas::Compiler::Frontend::LibNode
      converter.register_lib(node)
    when Adamas::Compiler::Frontend::AliasNode
      converter.register_alias(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end
  {converter, parsed.roots.last}
end

private def infer_extern_source_result(declarations : String, expression : String) : String?
  converter, expression_id = registered_extern_source_probe(declarations, expression)
  converter.__test_extern_source_result(expression_id)
end

describe "extern source result inference" do
  declarations = <<-CRYSTAL
    lib InferenceExitOracle
      alias Stop = NoReturn
      fun stop(value : Int32) : NoReturn
      fun aliased_stop(value : Int32) : Stop
      fun stop_without_args : NoReturn
      fun returning_void(value : Int32) : Void
      fun returning_int(value : Int32) : Int32
      fun same_symbol = stop(value : Int32) : Int32
    end
    alias ExitOracleAlias = InferenceExitOracle
    module ExitOracleScope
      class NoReturn
      end
      alias QualifiedExitAlias = InferenceExitOracle
    end
    CRYSTAL

  [
    "InferenceExitOracle.stop(1)",
    "InferenceExitOracle.aliased_stop(1)",
    "InferenceExitOracle.stop_without_args()",
    "InferenceExitOracle.stop_without_args",
    "::InferenceExitOracle.stop(1)",
    "ExitOracleAlias.stop(1)",
    "ExitOracleScope::QualifiedExitAlias.stop(1)",
    "::ExitOracleScope::QualifiedExitAlias.stop_without_args",
  ].each do |expression|
    it "keeps NoReturn source semantics for #{expression}" do
      infer_extern_source_result(declarations, expression).should eq("NoReturn")
    end
  end

  it "retains a returning Void ABI result without inventing NoReturn" do
    infer_extern_source_result(declarations, "InferenceExitOracle.returning_void(1)").should eq("Void")
  end

  it "retains canonical bottom when the caller shadows the NoReturn name" do
    converter, expression_id = registered_extern_source_probe(declarations, "InferenceExitOracle.stop(1)")
    converter.__test_extern_source_result(expression_id, "ExitOracleScope").should eq("NoReturn")
  end

  it "keeps the void ABI slot separate from the source NoReturn effect" do
    converter, expression_id = registered_extern_source_probe(declarations, "InferenceExitOracle.stop(1)")
    declaration = converter.module.get_extern_function("InferenceExitOracle", "stop").not_nil!
    declaration.return_type.should eq(Adamas::HIR::TypeRef::VOID)
    declaration.noreturn.should be_true
    converter.__test_extern_source_result(expression_id).should eq("NoReturn")
  end

  it "retains ordinary result types" do
    infer_extern_source_result(declarations, "InferenceExitOracle.returning_int(1)").should eq("Int32")
  end

  it "uses the selected declaration effect rather than the C symbol name" do
    infer_extern_source_result(declarations, "InferenceExitOracle.same_symbol(1)").should eq("Int32")
  end
end
