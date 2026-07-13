require "spec"

require "../../src/compiler/frontend/parser"

private def assert_explicit_indexer_call(source : String, method_name : String, argument_names : Array(String))
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program

  parser.diagnostics.should be_empty
  program.roots.size.should eq(1)

  arena = program.arena
  root = arena[program.roots.first]
  root.should be_a(Adamas::Compiler::Frontend::CallNode)
  call = root.as(Adamas::Compiler::Frontend::CallNode)

  # The explicit operator call must be one CallNode whose callee is the
  # operator member. A nested CallNode here would mean `[]`/`[]?` consumed no
  # arguments and the following parentheses were parsed as a result call.
  callee = arena[call.callee]
  callee.should be_a(Adamas::Compiler::Frontend::MemberAccessNode)
  member = callee.as(Adamas::Compiler::Frontend::MemberAccessNode)
  String.new(member.member).should eq(method_name)

  call.named_args.should be_nil
  call.args.size.should eq(argument_names.size)
  argument_names.each_with_index do |expected_name, index|
    argument = arena[call.args[index]]
    argument.should be_a(Adamas::Compiler::Frontend::IdentifierNode)
    String.new(argument.as(Adamas::Compiler::Frontend::IdentifierNode).name).should eq(expected_name)
  end
end

describe "Adamas::Compiler::Frontend::Parser" do
  describe "explicit dotted indexer operator calls" do
    it "preserves arguments for .[]" do
      assert_explicit_indexer_call("arena.[](arg)", "[]", ["arg"])
    end

    it "preserves arguments for .[]?" do
      assert_explicit_indexer_call("arena.[]?(arg)", "[]?", ["arg"])
    end

    it "preserves arguments for .[]=" do
      assert_explicit_indexer_call("arena.[]=(index, value)", "[]=", ["index", "value"])
    end

    it "preserves arguments for .[]?=" do
      assert_explicit_indexer_call("arena.[]?=(index, value)", "[]?=", ["index", "value"])
    end

    it "keeps a separated question mark as a ternary" do
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new("obj.[] ? (a) : b")
      )
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(1)
      arena = program.arena
      root = arena[program.roots.first]
      root.should be_a(Adamas::Compiler::Frontend::TernaryNode)
      condition = arena[root.as(Adamas::Compiler::Frontend::TernaryNode).condition]
      condition.should be_a(Adamas::Compiler::Frontend::IndexNode)
    end

    it "keeps a separated equals as ordinary index assignment" do
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new("obj.[] = (index, value)")
      )
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(1)
      arena = program.arena
      root = arena[program.roots.first]
      root.should be_a(Adamas::Compiler::Frontend::AssignNode)
      assignment = root.as(Adamas::Compiler::Frontend::AssignNode)
      arena[assignment.target].should be_a(Adamas::Compiler::Frontend::IndexNode)
      arena[assignment.value].should be_a(Adamas::Compiler::Frontend::TupleLiteralNode)
    end
  end
end
