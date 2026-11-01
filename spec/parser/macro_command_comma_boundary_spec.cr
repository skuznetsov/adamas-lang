require "spec"

require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/parser"

private def parse_macro_command_comma_boundary(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source), recovery_mode: false)
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program
end

private def parsed_macro_expressions(arena : Adamas::Compiler::Frontend::AstArena)
  arena.nodes.compact_map do |node|
    node.as?(Adamas::Compiler::Frontend::MacroExpressionNode)
  end
end

describe "Macro expression comma boundaries" do
  it "parses command-call commas with the macro expression grammar" do
    program = parse_macro_command_comma_boundary(%({{ raise "output failure", 29 }}))
    arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    program.roots.size.should eq(1)

    macro_expression = arena[program.roots.first].as(Adamas::Compiler::Frontend::MacroExpressionNode)
    macro_expression.output.should be_true
    call = arena[macro_expression.expression].as(Adamas::Compiler::Frontend::CallNode)
    call.args.size.should eq(2)
    arena[call.callee].as(Adamas::Compiler::Frontend::IdentifierNode).name.should eq("raise".to_slice)
  end

  it "keeps explicit-call commas inside the macro expression" do
    program = parse_macro_command_comma_boundary(%({{ raise("output failure", 29) }}))
    arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    macro_expression = arena[program.roots.first].as(Adamas::Compiler::Frontend::MacroExpressionNode)
    call = arena[macro_expression.expression].as(Adamas::Compiler::Frontend::CallNode)
    call.args.size.should eq(2)
  end

  it "keeps spaced nested tuple braces as a runtime tuple literal" do
    program = parse_macro_command_comma_boundary("{ {1, 2}, {3, 4} }")
    arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    outer = arena[program.roots.first].as(Adamas::Compiler::Frontend::TupleLiteralNode)
    outer.elements.size.should eq(2)
    outer.elements.each do |element|
      arena[element].as(Adamas::Compiler::Frontend::TupleLiteralNode).elements.size.should eq(2)
    end
  end

  it "keeps an immediately opened macro expression distinct from its nested tuple" do
    program = parse_macro_command_comma_boundary(%({{ {1, 2} }}))
    arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    macro_expression = arena[program.roots.first].as(Adamas::Compiler::Frontend::MacroExpressionNode)
    arena[macro_expression.expression].as(Adamas::Compiler::Frontend::TupleLiteralNode).elements.size.should eq(2)
  end

  it "parses a command-call comma inside a class method block" do
    program = parse_macro_command_comma_boundary(<<-CRYSTAL)
      class MacroOutputHost
        def render
          unrelated_call do
            {{ raise "class block failure", 41 }}
          end
        end
      end
      CRYSTAL
    arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    expressions = parsed_macro_expressions(arena)
    expressions.size.should eq(1)
    arena[expressions.first.expression].as(Adamas::Compiler::Frontend::CallNode).args.size.should eq(2)
  end

  it "leaves ordinary runtime hash commas on the runtime literal path" do
    program = parse_macro_command_comma_boundary("value = {1 => 2, 3 => 4}")
    arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    assignment = arena[program.roots.first].as(Adamas::Compiler::Frontend::AssignNode)
    arena[assignment.value].as(Adamas::Compiler::Frontend::HashLiteralNode).entries.size.should eq(2)
  end
  it "rejects an unspaced nested tuple that starts a macro expression" do
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("{{1, 2}, {3, 4}}"))
    parser.parse_program
    parser.diagnostics.should_not be_empty
  end

end
