require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/context"
require "../../src/compiler/semantic/macro_value"

include Adamas::Compiler

private def node_source_provider_for(
  arena : Frontend::ArenaLike,
  source : String,
) : Proc(Frontend::ExprId, String?)
  ->(expr_id : Frontend::ExprId) : String? do
    if expr_id.invalid? || expr_id.index < 0 || expr_id.index >= arena.size
      nil
    else
      span = arena[expr_id].span
      if span.start_offset < 0 || span.end_offset <= span.start_offset || span.end_offset > source.bytesize
        nil
      else
        source.byte_slice(span.start_offset, span.end_offset - span.start_offset)
      end
    end
  end
end

describe "MacroNodeValue source provider arena ownership" do
  it "keeps same-index, same-span nodes tied to their own source buffers" do
    left_source = "result = wrap( 65 )\n"
    right_source = "result = wrap(65  )\n"

    left_parser = Frontend::Parser.new(Frontend::Lexer.new(left_source))
    left_program = left_parser.parse_program
    left_parser.diagnostics.should be_empty
    left_arena = left_program.arena
    left_assignment_id = left_program.roots.find { |id| left_arena[id].is_a?(Frontend::AssignNode) }.not_nil!
    left_assignment = left_arena[left_assignment_id].as(Frontend::AssignNode)
    left_provider = node_source_provider_for(left_arena, left_source)
    left_value = Semantic::MacroNodeValue.new(
      left_assignment.value, left_arena, left_program.string_pool, left_provider, left_arena
    )

    right_parser = Frontend::Parser.new(Frontend::Lexer.new(right_source))
    right_program = right_parser.parse_program
    right_parser.diagnostics.should be_empty
    right_arena = right_program.arena
    right_assignment_id = right_program.roots.find { |id| right_arena[id].is_a?(Frontend::AssignNode) }.not_nil!
    right_assignment = right_arena[right_assignment_id].as(Frontend::AssignNode)
    right_provider = node_source_provider_for(right_arena, right_source)
    right_value = Semantic::MacroNodeValue.new(
      right_assignment.value, right_arena, right_program.string_pool, right_provider, right_arena
    )

    left_value.node_id.index.should eq(right_value.node_id.index)
    left_arena[left_value.node_id].span.start_offset.should eq(right_arena[right_value.node_id].span.start_offset)
    left_arena[left_value.node_id].span.end_offset.should eq(right_arena[right_value.node_id].span.end_offset)

    left_value.to_macro_output.should eq("wrap( 65 )")
    right_value.to_macro_output.should eq("wrap(65  )")
    left_value.stringify.should eq("wrap(65)")

    mismatched_owner = Semantic::MacroNodeValue.new(
      left_assignment.value, left_arena, left_program.string_pool, right_provider, right_arena
    )
    mismatched_owner.to_macro_output.should eq("wrap(65)")
  end
end
