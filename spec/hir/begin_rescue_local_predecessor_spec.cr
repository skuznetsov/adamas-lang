require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

private def lower_begin_rescue_predecessor_fixture(with_ensure : Bool) : Adamas::HIR::Function
  source = <<-CRYSTAL
    def exercise(flag : Bool) : Int32
      value = 11
      begin
        if flag
          value = 73
        else
          value = 29
        end
      rescue
        value = 41
      #{with_ensure ? "ensure\n    value = value + 5" : ""}
      end
      value
    end
    CRYSTAL
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  arena = result.arena
  definition = result.roots.find { |expr_id| arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode) }
  raise "missing exercise definition" unless definition
  Adamas::HIR::AstToHir.new(arena).lower_def(arena[definition].as(Adamas::Compiler::Frontend::DefNode))
end

describe "begin/rescue local predecessor identity" do
  [false, true].each do |with_ensure|
    it "uses actual completed body edges before #{with_ensure ? "ensure" : "continuation"}" do
      function = lower_begin_rescue_predecessor_fixture(with_ensure)
      phis = function.blocks.flat_map(&.instructions).select(Adamas::HIR::Phi)
      phis.size.should be >= 2
      function.blocks.each do |block|
        block.instructions.select(Adamas::HIR::Phi).each do |phi|
          phi.incoming_blocks.each do |predecessor_id|
            predecessor = function.blocks.find { |candidate| candidate.id == predecessor_id }
            predecessor.should_not be_nil
            predecessor.not_nil!.terminator.successors.should contain(block.id)
          end
        end
      end
    end
  end
end
