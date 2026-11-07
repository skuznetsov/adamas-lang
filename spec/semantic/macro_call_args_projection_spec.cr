require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/context"
require "../../src/compiler/semantic/macro_value"

include Adamas::Compiler

private def macro_call_args_source_provider_for(
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

private def macro_call_value_for(source : String) : {Semantic::MacroNodeValue, Frontend::Program}
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty

  call_id = program.roots.find do |id|
    node = program.arena[id]
    node.is_a?(Frontend::CallNode) || node.is_a?(Frontend::MemberAccessNode)
  end.not_nil!
  provider = macro_call_args_source_provider_for(program.arena, source)
  value = Semantic::MacroNodeValue.new(
    call_id, program.arena, program.string_pool, provider, program.arena
  )
  {value, program}
end

describe "MacroNodeValue Call#args projection" do
  it "returns an ArrayLiteral with source-owned child nodes" do
    call, program = macro_call_value_for("wrap( 65, 66 )\n")

    projected = call.call_method("args", [] of Semantic::MacroValue, nil)
    projected.should be_a(Semantic::MacroArrayValue)
    values = projected.as(Semantic::MacroArrayValue).elements
    values.size.should eq(2)
    values.each { |value| value.should be_a(Semantic::MacroNodeValue) }

    first = values[0].as(Semantic::MacroNodeValue)
    second = values[1].as(Semantic::MacroNodeValue)
    first.arena.same?(program.arena).should be_true
    second.arena.same?(program.arena).should be_true
    first.node_source_provider_arena.not_nil!.same?(program.arena).should be_true
    first.to_macro_output.should eq("65")
    second.to_macro_output.should eq("66")
  end

  it "keeps equal-index and equal-span children tied to different arena buffers" do
    left_call, left_program = macro_call_value_for("wrap( 65 )\n")
    right_call, right_program = macro_call_value_for("wrap( 66 )\n")

    left = left_call.call_method("args", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroArrayValue).elements.first.as(Semantic::MacroNodeValue)
    right = right_call.call_method("args", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroArrayValue).elements.first.as(Semantic::MacroNodeValue)

    left.node_id.index.should eq(right.node_id.index)
    left_span = left_program.arena[left.node_id].span
    right_span = right_program.arena[right.node_id].span
    left_span.start_offset.should eq(right_span.start_offset)
    left_span.end_offset.should eq(right_span.end_offset)
    left.arena.same?(left_program.arena).should be_true
    right.arena.same?(right_program.arena).should be_true
    left.to_macro_output.should eq("65")
    right.to_macro_output.should eq("66")
  end

  it "keeps an empty call's args as an empty ArrayLiteral" do
    call, _program = macro_call_value_for("wrap()\n")

    projected = call.call_method("args", [] of Semantic::MacroValue, nil)
    projected.should be_a(Semantic::MacroArrayValue)
    projected.class_name.should eq("ArrayLiteral")
    projected.as(Semantic::MacroArrayValue).elements.should be_empty
  end

  it "does not turn args on a non-call node into an empty array" do
    parser = Frontend::Parser.new(Frontend::Lexer.new("65\n"))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    literal = Semantic::MacroNodeValue.new(
      program.roots.first, program.arena, program.string_pool,
      macro_call_args_source_provider_for(program.arena, "65\n"), program.arena
    )

    literal.call_method("args", [] of Semantic::MacroValue, nil).should be_a(Semantic::MacroNilValue)
  end

  it "rejects arguments passed to the zero-argument args projection" do
    call, _program = macro_call_value_for("wrap(65)\n")
    extra = Semantic::MacroNumberValue.new(1_i64)

    expect_raises(ArgumentError, "Call#args expects no arguments") do
      call.call_method("args", [extra] of Semantic::MacroValue, nil)
    end
  end

  it "projects a definite no-parentheses member call as Call" do
    call, program = macro_call_value_for("Target.consume\n")

    program.arena[call.node_id].should be_a(Frontend::MemberAccessNode)
    call.class_name.should eq("Call")
    call.call_method("name", [] of Semantic::MacroValue, nil).to_id.should eq("consume")
    call.call_method("args", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroArrayValue).elements.should be_empty
    call.call_method("named_args", [] of Semantic::MacroValue, nil)
      .should be_a(Semantic::MacroNopValue)

    receiver = call.call_method("receiver", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroNodeValue)
    receiver.arena.same?(program.arena).should be_true
    receiver.to_macro_output.should eq("Target")
  end

  it "projects a parenthesized member call's receiver and method name" do
    call, program = macro_call_value_for("Target.consume(65)\n")

    call.call_method("name", [] of Semantic::MacroValue, nil).to_id.should eq("consume")
    receiver = call.call_method("receiver", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroNodeValue)
    receiver.arena.same?(program.arena).should be_true
    receiver.node_source_provider_arena.not_nil!.same?(program.arena).should be_true
    receiver.to_macro_output.should eq("Target")
    call.call_method("args", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroArrayValue).elements.first.to_macro_output.should eq("65")
  end

  it "projects a bare function Call with Nop receiver and source-owned name" do
    call, _program = macro_call_value_for("consume(65)\n")

    call.call_method("name", [] of Semantic::MacroValue, nil).to_id.should eq("consume")
    call.call_method("receiver", [] of Semantic::MacroValue, nil)
      .should be_a(Semantic::MacroNopValue)
  end

  it "projects named arguments in order and keeps each value child with its owner" do
    left_call, left_program = macro_call_value_for("consume(left: 65, right: 66)\n")
    right_call, right_program = macro_call_value_for("consume(left: 67, right: 68)\n")

    left_args = left_call.call_method("named_args", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroArrayValue).elements
    right_args = right_call.call_method("named_args", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroArrayValue).elements
    left_args.size.should eq(2)
    right_args.size.should eq(2)

    left_first = left_args.first.as(Semantic::MacroNamedArgumentValue)
    left_second = left_args[1].as(Semantic::MacroNamedArgumentValue)
    right_first = right_args.first.as(Semantic::MacroNamedArgumentValue)
    left_first.class_name.should eq("NamedArgument")
    left_first.call_method("name", [] of Semantic::MacroValue, nil).to_id.should eq("left")
    left_second.call_method("name", [] of Semantic::MacroValue, nil).to_id.should eq("right")

    left_value = left_first.call_method("value", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroNodeValue)
    right_value = right_first.call_method("value", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroNodeValue)
    left_value.arena.same?(left_program.arena).should be_true
    right_value.arena.same?(right_program.arena).should be_true
    left_value.node_source_provider_arena.not_nil!.same?(left_program.arena).should be_true
    left_value.string_pool.not_nil!.same?(left_program.string_pool).should be_true
    left_value.to_macro_output.should eq("65")
    right_value.to_macro_output.should eq("67")

    extra = Semantic::MacroNumberValue.new(1_i64)
    expect_raises(ArgumentError, "NamedArgument#value expects no arguments") do
      left_first.call_method("value", [extra] of Semantic::MacroValue, nil)
    end
  end

  it "projects single and double splat operands without losing node ownership" do
    single_call, single_program = macro_call_value_for("consume(*values)\n")
    double_call, double_program = macro_call_value_for("consume(**options)\n")

    single = single_call.call_method("args", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroArrayValue).elements.first.as(Semantic::MacroNodeValue)
    double = double_call.call_method("args", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroArrayValue).elements.first.as(Semantic::MacroNodeValue)
    single.class_name.should eq("Splat")
    double.class_name.should eq("DoubleSplat")

    single_exp = single.call_method("exp", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroNodeValue)
    double_exp = double.call_method("exp", [] of Semantic::MacroValue, nil)
      .as(Semantic::MacroNodeValue)
    single_exp.arena.same?(single_program.arena).should be_true
    double_exp.arena.same?(double_program.arena).should be_true
    single_exp.node_source_provider_arena.not_nil!.same?(single_program.arena).should be_true
    double_exp.to_macro_output.should eq("options")
  end

  it "does not invent a missing receiver for an unsupported Call callee" do
    parser = Frontend::Parser.new(Frontend::Lexer.new("65\n"))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    literal_id = program.roots.first
    span = program.arena[literal_id].span
    call_id = program.arena.add(Frontend::CallNode.new(span, literal_id, [] of Frontend::ExprId))
    unsupported = Semantic::MacroNodeValue.new(
      call_id, program.arena, program.string_pool
    )

    expect_raises(ArgumentError, "unsupported Call#receiver callee shape") do
      unsupported.call_method("receiver", [] of Semantic::MacroValue, nil)
    end
    expect_raises(ArgumentError, "unsupported Call#name callee shape") do
      unsupported.call_method("name", [] of Semantic::MacroValue, nil)
    end
  end
end
