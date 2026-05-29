require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Generic arguments with tuple and named tuple types" do
    it "parses generic with tuple type arguments" do
      source = "Foo({X, Y})"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)
    end

    it "parses generic with named tuple type arguments" do
      source = "Foo({x: X, y: Y})"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)
    end
  end
end
