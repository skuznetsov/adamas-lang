require "spec"
require "../../src/compiler/frontend/parser"

alias MacroBlockBoundaryFrontend = Adamas::Compiler::Frontend

private def macro_block_boundary_program(body : String)
  source = "{% entries = items.map do |ivar|\n#{body}\nend %}"
  parser = MacroBlockBoundaryFrontend::Parser.new(MacroBlockBoundaryFrontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program
end

private def macro_block_boundary_body(body : String)
  program = macro_block_boundary_program(body)
  block = program.ast_arena.nodes.select(MacroBlockBoundaryFrontend::BlockNode).last
  {program, block.body}
end

describe "macro block statement boundaries after parenthesized calls" do
  [
    "anno = ivar.annotation(IniOpt)\n{transform: anno[:transform] || ivar.type}",
    "anno = ivar.annotation(\nIniOpt\n)\n{transform: anno[:transform] || ivar.type}",
    "anno = ivar.annotation(IniOpt); {transform: anno[:transform] || ivar.type}",
  ].each do |body|
    it "preserves the assignment and following named tuple in #{body.inspect}" do
      program, statements = macro_block_boundary_body(body)
      statements.size.should eq(2)
      assign = program.arena[statements.first].as(MacroBlockBoundaryFrontend::AssignNode)
      call = program.arena[assign.value].as(MacroBlockBoundaryFrontend::CallNode)
      call.block.should be_nil
      tuple = program.arena[statements.last].as(MacroBlockBoundaryFrontend::NamedTupleLiteralNode)
      tuple.entries.size.should eq(1)
      program.arena[tuple.entries.first.value].should be_a(MacroBlockBoundaryFrontend::BinaryNode)
    end
  end

  ["{ 42 }", "do\n42\nend"].each do |block_source|
    it "retains a trailing block on the closing-parenthesis line: #{block_source.inspect}" do
      program, statements = macro_block_boundary_body("anno = ivar.annotation(IniOpt) #{block_source}")
      statements.size.should eq(1)
      assign = program.arena[statements.first].as(MacroBlockBoundaryFrontend::AssignNode)
      call = program.arena[assign.value].as(MacroBlockBoundaryFrontend::CallNode)
      block = program.arena[call.block.not_nil!].as(MacroBlockBoundaryFrontend::BlockNode)
      block.body.size.should eq(1)
      program.arena[block.body.first].should be_a(MacroBlockBoundaryFrontend::NumberNode)
    end
  end
end
