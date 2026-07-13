require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def parse_try_return_spec(code : String) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

private def lower_try_return_function(code : String) : Adamas::HIR::Function
  arena, exprs = parse_try_return_spec(code)
  converter = Adamas::HIR::AstToHir.new(arena)
  def_expr = exprs.find { |expr_id| arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode) }
  raise "No function definition found" unless def_expr
  converter.lower_def(arena[def_expr].as(Adamas::Compiler::Frontend::DefNode))
end

describe "HIR rescue return cleanup" do
  it "pops the protected handler before an early return from a nested branch" do
    func = lower_try_return_function(<<-CRYSTAL)
      def probe(cond : Bool, value : Int32) : Int32
        begin
          if cond
            return value
          end
          value + 1
        rescue
          value
        end
      end
    CRYSTAL

    try_begins = func.blocks.flat_map(&.instructions).count { |instruction| instruction.is_a?(Adamas::HIR::TryBegin) }
    try_ends = func.blocks.flat_map(&.instructions).count { |instruction| instruction.is_a?(Adamas::HIR::TryEnd) }
    try_begins.should eq(1)

    return_blocks = func.blocks.select { |block| block.terminator.is_a?(Adamas::HIR::Return) }
    return_blocks.size.should be >= 2

    # The explicit `return value` branch has no value-producing instruction of
    # its own. It must carry its handler pop in the same block before Return.
    early_return_blocks = return_blocks.select do |block|
      block.instructions.any? do |instruction|
        literal = instruction.as?(Adamas::HIR::Literal)
        literal && literal.value.is_a?(Nil)
      end
    end
    early_return_blocks.size.should eq(1)
    early_return_blocks.first.instructions.count { |instruction| instruction.is_a?(Adamas::HIR::TryEnd) }.should eq(1)

    # One pop belongs to the normal protected-body fallthrough, one to the
    # exception path before entering rescue, and one to the early-return edge.
    try_ends.should eq(3)

    normal_fallthrough_blocks = func.blocks.select do |block|
      block.instructions.any? { |instruction| instruction.is_a?(Adamas::HIR::BinaryOperation) } &&
        block.instructions.any? { |instruction| instruction.is_a?(Adamas::HIR::TryEnd) }
    end
    normal_fallthrough_blocks.size.should eq(1)
    normal_fallthrough_blocks.first.instructions.count { |instruction| instruction.is_a?(Adamas::HIR::TryEnd) }.should eq(1)

    rescue_blocks = func.blocks.select do |block|
      block.instructions.any? { |instruction| instruction.is_a?(Adamas::HIR::GetException) }
    end
    rescue_blocks.size.should eq(1)
    rescue_blocks.first.instructions.count { |instruction| instruction.is_a?(Adamas::HIR::TryEnd) }.should eq(1)

    # No fallthrough block may pop the same handler twice.
    func.blocks.each do |block|
      block.instructions.count { |instruction| instruction.is_a?(Adamas::HIR::TryEnd) }.should be <= 1
    end
  end

  it "keeps an outer rescue active while an inner ensure runs" do
    func = lower_try_return_function(<<-CRYSTAL)
      def nested(cond : Bool, value : Int32) : Int32
        begin
          begin
            if cond
              return value
            end
            value + 1
          ensure
            value + 2
          end
        rescue
          value
        end
      end
    CRYSTAL

    early_return = func.blocks.select { |block| block.terminator.is_a?(Adamas::HIR::Return) }
      .find do |block|
        block.instructions.any? do |instruction|
          literal = instruction.as?(Adamas::HIR::Literal)
          literal && literal.value.is_a?(Nil)
        end
      end
    early_return.should_not be_nil
    early_return = early_return.not_nil!

    ensure_add_index = early_return.instructions.index do |instruction|
      binary = instruction.as?(Adamas::HIR::BinaryOperation)
      binary && binary.op == Adamas::HIR::BinaryOp::Add
    end
    try_end_index = early_return.instructions.index { |instruction| instruction.is_a?(Adamas::HIR::TryEnd) }
    ensure_add_index.should_not be_nil
    try_end_index.should_not be_nil
    ensure_add_index.not_nil!.should be < try_end_index.not_nil!
  end

  it "pops nested rescue handlers from the inner scope outward" do
    func = lower_try_return_function(<<-CRYSTAL)
      def nested_rescue(cond : Bool, value : Int32) : Int32
        begin
          begin
            if cond
              return value
            end
            value + 1
          rescue
            value + 2
          end
        rescue
          value + 3
        end
      end
    CRYSTAL

    early_return = func.blocks.select { |block| block.terminator.is_a?(Adamas::HIR::Return) }
      .find do |block|
        block.instructions.any? do |instruction|
          literal = instruction.as?(Adamas::HIR::Literal)
          literal && literal.value.is_a?(Nil)
        end
      end
    early_return.should_not be_nil
    early_return.not_nil!.instructions.count { |instruction| instruction.is_a?(Adamas::HIR::TryEnd) }.should eq(2)
  end

  it "leaves the handler installed for a raise in the protected body" do
    func = lower_try_return_function(<<-CRYSTAL)
      def raise_probe : Int32
        begin
          raise "boom"
        rescue
          42
        end
      end
    CRYSTAL

    raise_blocks = func.blocks.select do |block|
      block.instructions.any? { |instruction| instruction.is_a?(Adamas::HIR::Raise) }
    end
    raise_blocks.size.should eq(1)
    raise_blocks.first.instructions.none? { |instruction| instruction.is_a?(Adamas::HIR::TryEnd) }.should be_true
  end
end
