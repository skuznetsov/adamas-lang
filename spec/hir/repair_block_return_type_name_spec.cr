require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

# Test-only access to the helper used by receiver-bound block-call repair.
class Adamas::HIR::AstToHir
  def __test_repair_block_return_type_name(
    func : Adamas::HIR::Function,
    block_id : Adamas::HIR::BlockId,
    value_types : Hash(Adamas::HIR::ValueId, Adamas::HIR::TypeRef),
  ) : String?
    repair_block_return_type_name(func, block_id, value_types)
  end
end

describe "block return type repair" do
  it "fails closed for a stale block id" do
    parsed = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("")
    ).parse_program
    converter = Adamas::HIR::AstToHir.new(parsed.arena)
    function = converter.module.create_function("stale_block", Adamas::HIR::TypeRef::VOID)
    entry = function.get_block(function.entry_block)

    stale_block_id = function.blocks.size.to_u32
    call = Adamas::HIR::Call.without_receiver_block(
      function.next_value_id,
      Adamas::HIR::TypeRef::VOID,
      "Owner#yielding",
      [] of Adamas::HIR::ValueId,
      stale_block_id,
      false,
    )
    entry.add(call)

    converter.__test_repair_block_return_type_name(
      function,
      call.block.not_nil!,
      {} of Adamas::HIR::ValueId => Adamas::HIR::TypeRef,
    ).should be_nil
  end
end
