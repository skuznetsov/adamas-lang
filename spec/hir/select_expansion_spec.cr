require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_expand_select(expression : Adamas::Compiler::Frontend::ExprId)
    expand_select(@arena[expression].as(Adamas::Compiler::Frontend::SelectNode))
  end
end

module SelectExpansionSpec
  alias F = Adamas::Compiler::Frontend

  def self.expand(source : String)
    parser = F::Parser.new(F::Lexer.new(source))
    parsed = parser.parse_program
    parser.diagnostics.should be_empty
    converter = Adamas::HIR::AstToHir.new(parsed.arena)
    original = parsed.arena[parsed.roots.first].as(F::SelectNode)
    expanded = converter.__test_expand_select(parsed.roots.first)
    {parsed.arena, original, expanded, converter, parsed.roots.first}
  end

  def self.dispatch(arena, expanded)
    multi = arena[expanded.body.first].as(F::MultipleAssignNode)
    arena[multi.value].as(F::CallNode)
  end

  def self.actions(arena, expanded)
    call = dispatch(arena, expanded)
    arena[call.args.first].as(F::TupleLiteralNode).elements.map { |id| arena[id].as(F::CallNode) }
  end
end

describe "select literal expansion" do
  it "creates one action per branch and preserves punctuation" do
    arena, original, expanded = SelectExpansionSpec.expand("select\nwhen stream.receive\nwhen stream.receive?\nwhen stream.send!(42)\nend")
    actions = SelectExpansionSpec.actions(arena, expanded)
    actions.map { |action| String.new(arena[action.callee].as(SelectExpansionSpec::F::MemberAccessNode).member) }.should eq([
      "receive_select_action", "receive_select_action?", "send_select_action!",
    ])
    actions.last.args.size.should eq(1)
    original.branches.size.should eq(3)
  end

  it "preserves receiver, arguments, named arguments, and the block without cloning effects" do
    arena, original, expanded = SelectExpansionSpec.expand("select\nwhen stream.send(42, timeout: delay) { |x| x }\nend")
    original_call = arena[original.branches.first.condition].as(SelectExpansionSpec::F::CallNode)
    action = SelectExpansionSpec.actions(arena, expanded).first
    action.args.should eq(original_call.args)
    action.named_args.should eq(original_call.named_args)
    action.block.should eq(original_call.block)
    arena[action.callee].as(SelectExpansionSpec::F::MemberAccessNode).object.should eq(
      arena[original_call.callee].as(SelectExpansionSpec::F::MemberAccessNode).object)
  end

  it "uses the global Channel and blocking select without an else branch" do
    arena, _, expanded = SelectExpansionSpec.expand("select\nwhen stream.receive\nend")
    dispatch = SelectExpansionSpec.dispatch(arena, expanded)
    callee = arena[dispatch.callee].as(SelectExpansionSpec::F::MemberAccessNode)
    String.new(callee.member).should eq("select")
    path = arena[callee.object].as(SelectExpansionSpec::F::PathNode)
    path.left.should be_nil
    String.new(arena[path.right].as(SelectExpansionSpec::F::IdentifierNode).name).should eq("Channel")
    case_node = arena[expanded.body.last].as(SelectExpansionSpec::F::CaseNode)
    arena[case_node.else_branch.not_nil!.first].should be_a(SelectExpansionSpec::F::RaiseNode)
  end

  it "uses non_blocking_select even for an empty else branch" do
    arena, original, expanded = SelectExpansionSpec.expand("select\nwhen stream.receive\nelse\nend")
    callee = arena[SelectExpansionSpec.dispatch(arena, expanded).callee].as(SelectExpansionSpec::F::MemberAccessNode)
    String.new(callee.member).should eq("non_blocking_select")
    case_node = arena[expanded.body.last].as(SelectExpansionSpec::F::CaseNode)
    case_node.else_branch.should eq(original.else_branch)
  end

  it "casts only the selected assignment from semantic typeof of its original operation" do
    arena, original, expanded = SelectExpansionSpec.expand("select\nwhen value = stream.receive?\n  value\nend")
    assign = arena[original.branches.first.condition].as(SelectExpansionSpec::F::AssignNode)
    case_node = arena[expanded.body.last].as(SelectExpansionSpec::F::CaseNode)
    body = case_node.when_branches.first.body
    generated = arena[body.first].as(SelectExpansionSpec::F::AssignNode)
    generated.target.should eq(assign.target)
    cast = arena[generated.value].as(SelectExpansionSpec::F::CallNode)
    arena[cast.args.first].as(SelectExpansionSpec::F::TypeofNode).args.should eq([assign.value])
    body[1..].should eq(original.branches.first.body)
    original.branches.first.body.size.should eq(1)
  end

  it "uses contiguous zero-based indexes for dispatch" do
    arena, _, expanded = SelectExpansionSpec.expand("select\nwhen first.receive\nwhen second.receive\nend")
    case_node = arena[expanded.body.last].as(SelectExpansionSpec::F::CaseNode)
    case_node.when_branches.map { |branch| String.new(arena[branch.conditions.first].as(SelectExpansionSpec::F::NumberNode).value) }.should eq(["0", "1"])
  end

  it "allocates different inaccessible local names on each expansion" do
    arena, _, expanded, converter, expression = SelectExpansionSpec.expand("select\nwhen stream.receive\nend")
    second = converter.__test_expand_select(expression)
    first_targets = arena[expanded.body.first].as(SelectExpansionSpec::F::MultipleAssignNode).targets
    second_targets = arena[second.body.first].as(SelectExpansionSpec::F::MultipleAssignNode).targets
    names = (first_targets + second_targets).map { |target| String.new(arena[target].as(SelectExpansionSpec::F::IdentifierNode).name) }
    names.uniq.size.should eq(4)
    names.each { |name| name.should start_with("$select_") }
  end

  it "rejects a condition that cannot become a selection action" do
    expect_raises(Adamas::HIR::LoweringError, "select condition must be a call") do
      SelectExpansionSpec.expand("select\nwhen 42\nend")
    end
  end

  it "retains a globally qualified operation's path" do
    arena, _, expanded = SelectExpansionSpec.expand("select\nwhen ::timeout(42)\nend")
    action = SelectExpansionSpec.actions(arena, expanded).first
    path = arena[action.callee].as(SelectExpansionSpec::F::PathNode)
    path.left.should be_nil
    String.new(arena[path.right].as(SelectExpansionSpec::F::IdentifierNode).name).should eq("timeout_select_action")
    action.args.size.should eq(1)
  end
end
