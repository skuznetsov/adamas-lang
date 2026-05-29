require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  it "allows using 'out' as a regular identifier in expressions" do
    source = <<-CRYSTAL
    def foo(out : Int32)
      out = out + 1
      out
    end
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    parser.diagnostics.should be_empty

    # method body assigns to `out` without treating it as the out-parameter syntax
    arena = program.arena
    def_node = arena[program.roots[0]].as(Adamas::Compiler::Frontend::DefNode)
    body = def_node.body.not_nil!
    # last expression is identifier "out"
    last_expr = arena[body.last]
    Adamas::Compiler::Frontend.node_kind(last_expr).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
  end
end
