require "spec"
require "../../src/compiler/frontend/parser"

private def parse_yield_member_expression(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program.roots.size.should eq(1)
  program
end

private def expect_yield_tap_receiver(source : String, argument_count : Int32 = 0)
  program = parse_yield_member_expression(source)
  arena = program.arena
  call = arena[program.roots.first].as(Adamas::Compiler::Frontend::CallNode)
  member = arena[call.callee].as(Adamas::Compiler::Frontend::MemberAccessNode)
  String.new(member.member).should eq("tap")
  receiver_node = arena[member.object]
  if receiver_node.is_a?(Adamas::Compiler::Frontend::GroupingNode)
    receiver_node = arena[receiver_node.expression]
  end
  receiver = receiver_node.as(Adamas::Compiler::Frontend::YieldNode)
  (receiver.args.try(&.size) || 0).should eq(argument_count)
  call.block.should_not be_nil
end

describe "yield as a member receiver" do
  it "attaches a brace block to a call on the yielded result" do
    expect_yield_tap_receiver("yield.tap { finish }")
  end

  it "attaches a do block to a call on the yielded result" do
    expect_yield_tap_receiver("yield.tap do\nfinish\nend")
  end

  it "retains a member receiver after whitespace or a continued newline" do
    expect_yield_tap_receiver("yield .tap { finish }")
    expect_yield_tap_receiver("yield\n.tap { finish }")
  end

  it "preserves explicit empty and nonempty yield arguments" do
    expect_yield_tap_receiver("yield().tap { finish }")
    expect_yield_tap_receiver("yield(1).tap { finish }", 1)
  end

  it "preserves grouping around the yield receiver" do
    expect_yield_tap_receiver("(yield).tap { finish }")
  end

  it "keeps member calls inside actual nonparenthesized yield arguments" do
    program = parse_yield_member_expression("yield value.tap { finish }")
    arena = program.arena
    node = arena[program.roots.first].as(Adamas::Compiler::Frontend::YieldNode)
    args = node.args.not_nil!
    args.size.should eq(1)
    call = arena[args.first].as(Adamas::Compiler::Frontend::CallNode)
    member = arena[call.callee].as(Adamas::Compiler::Frontend::MemberAccessNode)
    String.new(member.member).should eq("tap")
    arena[member.object].should be_a(Adamas::Compiler::Frontend::IdentifierNode)
    call.block.should_not be_nil
  end

  it "keeps multiple arguments and a postfix condition attached to yield" do
    program = parse_yield_member_expression("yield 1, 2 if ready")
    arena = program.arena
    condition = arena[program.roots.first].as(Adamas::Compiler::Frontend::IfNode)
    yielded = arena[condition.then_body.first].as(Adamas::Compiler::Frontend::YieldNode)
    yielded.args.not_nil!.size.should eq(2)
  end
end
