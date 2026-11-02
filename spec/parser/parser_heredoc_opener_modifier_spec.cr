require "spec"

require "../../src/compiler/frontend/parser"

alias HeredocOpenerModifierFrontend = Adamas::Compiler::Frontend

private def parse_heredoc_opener_modifier(source : String)
  parser = HeredocOpenerModifierFrontend::Parser.new(
    HeredocOpenerModifierFrontend::Lexer.new(source)
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  {program, program.arena}
end

private def assert_heredoc_raise_modifier(source : String, unless_modifier : Bool, condition_value : Bool)
  program, arena = parse_heredoc_opener_modifier(source)
  program.roots.size.should eq(1)

  macro_expression = arena[program.roots.first].as(HeredocOpenerModifierFrontend::MacroExpressionNode)
  macro_expression.output.should be_false

  if unless_modifier
    modifier = arena[macro_expression.expression].as(HeredocOpenerModifierFrontend::UnlessNode)
    condition_id = modifier.condition
    body = modifier.then_branch
  else
    modifier = arena[macro_expression.expression].as(HeredocOpenerModifierFrontend::IfNode)
    condition_id = modifier.condition
    body = modifier.then_body
  end

  arena[condition_id].as(HeredocOpenerModifierFrontend::BoolNode).value.should eq(condition_value)
  body.size.should eq(1)

  raise_call = arena[body.first].as(HeredocOpenerModifierFrontend::CallNode)
  callee = arena[raise_call.callee].as(HeredocOpenerModifierFrontend::IdentifierNode)
  String.new(callee.name).should eq("raise")
  raise_call.args.size.should eq(1)
  arena[raise_call.args.first].should be_a(HeredocOpenerModifierFrontend::StringNode)
end

describe "postfix modifiers on macro heredoc statements" do
  it "associates a heredoc raise with postfix if" do
    source = "{% raise <<-TXT if false\n  false guard must not raise\n  TXT\n%}"
    assert_heredoc_raise_modifier(source, unless_modifier: false, condition_value: false)
  end

  it "associates a heredoc raise with postfix unless" do
    source = "{% raise <<-TXT unless true\n  guard is not taken\n  TXT\n%}"
    assert_heredoc_raise_modifier(source, unless_modifier: true, condition_value: true)
  end

  it "retains the same statement shape for a regular string control" do
    source = "{% raise \"literal guard must not raise\" if false %}"
    assert_heredoc_raise_modifier(source, unless_modifier: false, condition_value: false)
  end

  it "preserves a parenthesized call's sibling argument after a heredoc" do
    source = "sink(<<-TXT, 7)\n  payload\n  TXT\n"
    program, arena = parse_heredoc_opener_modifier(source)
    call = arena[program.roots.first].as(HeredocOpenerModifierFrontend::CallNode)

    call.args.size.should eq(2)
    arena[call.args[0]].should be_a(HeredocOpenerModifierFrontend::StringNode)
    arena[call.args[1]].should be_a(HeredocOpenerModifierFrontend::NumberNode)
  end

  it "preserves multiple parenthesized heredoc arguments in source order" do
    source = "sink(<<-FIRST, <<-SECOND)\n  first body\n  FIRST\n  second body\n  SECOND\n"
    program, arena = parse_heredoc_opener_modifier(source)
    call = arena[program.roots.first].as(HeredocOpenerModifierFrontend::CallNode)

    call.args.size.should eq(2)
    first = arena[call.args[0]].as(HeredocOpenerModifierFrontend::StringNode)
    second = arena[call.args[1]].as(HeredocOpenerModifierFrontend::StringNode)
    String.new(first.value).should contain("first body")
    String.new(second.value).should contain("second body")
  end
end
