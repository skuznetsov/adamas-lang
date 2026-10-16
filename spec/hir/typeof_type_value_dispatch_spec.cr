require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_typeof_value_expression(source : String, local_type : Adamas::HIR::TypeRef? = nil)
  source = "struct Int32\nend\nstruct Int64\nend\n" + source
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  parsed.roots.each do |root|
    node = parsed.arena[root]
    converter.register_class(node) if node.is_a?(Adamas::Compiler::Frontend::ClassNode)
    converter.register_function(node) if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  function = converter.module.create_function("typeof_value_probe", Adamas::HIR::TypeRef::NIL)
  ctx = Adamas::HIR::LoweringContext.new(function, converter.module, parsed.arena)
  if local_type
    param = function.add_param("value", local_type)
    ctx.register_local("value", param.id)
    ctx.register_type(param.id, local_type)
  end
  result = converter.lower_expr(ctx, parsed.roots.last)
  {result, ctx, function}
end

private def typeof_value_literal(function : Adamas::HIR::Function, id : Adamas::HIR::ValueId)
  function.blocks.flat_map(&.instructions).find { |instruction| instruction.id == id }.as(Adamas::HIR::Literal)
end

describe "typeof type values in member dispatch" do
  it "registers a known semantic type as a type value" do
    id, ctx, _ = lower_typeof_value_expression("typeof(1)")
    ctx.type_literal?(id).should be_true
    ctx.type_of(id).should eq(Adamas::HIR::TypeRef::INT32)
    identity = ctx.runtime_type_identity?(id).not_nil!
    identity.semantic_type.should eq(Adamas::HIR::TypeRef::INT32)
    identity.origin.typeof?.should be_true
  end

  it "lowers a member name query without dispatching to Nil" do
    id, _, function = lower_typeof_value_expression("typeof(1).name")
    typeof_value_literal(function, id).str_value.should eq("Int32")
    function.blocks.flat_map(&.instructions).select(Adamas::HIR::Call).should be_empty
  end

  it "handles a parenthesized name call through the same type-value contract" do
    id, _, function = lower_typeof_value_expression("typeof(1).name()")
    typeof_value_literal(function, id).str_value.should eq("Int32")
  end

  it "preserves parentheses around a union display name" do
    id, _, function = lower_typeof_value_expression("typeof(1, 2_i64).name")
    typeof_value_literal(function, id).str_value.should eq("(Int32 | Int64)")
  end

  it "preserves a union type through a parenthesized member call" do
    id, _, function = lower_typeof_value_expression("typeof(1, 2_i64).name()")
    typeof_value_literal(function, id).str_value.should eq("(Int32 | Int64)")
  end

  it "uses an active local binding for member dispatch" do
    id, _, function = lower_typeof_value_expression("typeof(value).name", Adamas::HIR::TypeRef::INT64)
    typeof_value_literal(function, id).str_value.should eq("Int64")
  end

  it "uses an active local binding for a parenthesized member call" do
    id, _, function = lower_typeof_value_expression("typeof(value).name()", Adamas::HIR::TypeRef::INT64)
    typeof_value_literal(function, id).str_value.should eq("Int64")
  end

  it "does not lower the expression whose type is queried" do
    id, _, function = lower_typeof_value_expression(<<-CRYSTAL)
      def type_only_side_effect : Int32
        65
      end
      typeof(type_only_side_effect).name
    CRYSTAL
    typeof_value_literal(function, id).str_value.should eq("Int32")
    function.blocks.flat_map(&.instructions).select(Adamas::HIR::Call).should be_empty
  end
end
