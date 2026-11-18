require "../src/compiler/frontend/ast"

def validate_call_node(live : Bool)
  span = Adamas::Compiler::Frontend::Span.zero
  callee = Adamas::Compiler::Frontend::ExprId.new(3)
  args = [Adamas::Compiler::Frontend::ExprId.new(5)]
  named = [Adamas::Compiler::Frontend::NamedArgument.new("param".to_slice, Adamas::Compiler::Frontend::ExprId.new(7), span, span)]
  first = Adamas::Compiler::Frontend::CallNode.new(span, callee, args)
  second = Adamas::Compiler::Frontend::CallNode.new(span, callee, args, Adamas::Compiler::Frontend::ExprId.new(11))
  LibC.exit(91) if first.has_block? || !second.has_block?

  block_id = live ? Adamas::Compiler::Frontend::ExprId.new(13) : nil
  node = Adamas::Compiler::Frontend::CallNode.new(span, callee, args, block_id, named)
  LibC.exit(92) if node.has_block? != live
  if block_value = node.block
    LibC.exit(93) unless block_value.index == 13
  end
  actual = node.named_args
  LibC.exit(94) unless actual && actual.size == 1 && actual[0].value.index == 7
end

class WholeUnionCallNode
  getter kind : String

  def initialize(span : Adamas::Compiler::Frontend::Span, callee : Adamas::Compiler::Frontend::ExprId, args : Array(Adamas::Compiler::Frontend::ExprId))
    @kind = "base"
  end

  def initialize(span : Adamas::Compiler::Frontend::Span, callee : Adamas::Compiler::Frontend::ExprId, args : Array(Adamas::Compiler::Frontend::ExprId), block : Adamas::Compiler::Frontend::ExprId)
    @kind = "four-argument"
  end

  def initialize(span : Adamas::Compiler::Frontend::Span, callee : Adamas::Compiler::Frontend::ExprId, args : Array(Adamas::Compiler::Frontend::ExprId), block : Nil | Adamas::Compiler::Frontend::ExprId, named : Array(Adamas::Compiler::Frontend::NamedArgument))
    @kind = block ? "whole-union-expression" : "whole-union-nil"
  end
end

def validate_whole_union_call_node(live : Bool)
  span = Adamas::Compiler::Frontend::Span.zero
  callee = Adamas::Compiler::Frontend::ExprId.new(3)
  args = [Adamas::Compiler::Frontend::ExprId.new(5)]
  named = [Adamas::Compiler::Frontend::NamedArgument.new("param".to_slice, Adamas::Compiler::Frontend::ExprId.new(7), span, span)]
  WholeUnionCallNode.new(span, callee, args)
  WholeUnionCallNode.new(span, callee, args, Adamas::Compiler::Frontend::ExprId.new(11))
  block_id = live ? Adamas::Compiler::Frontend::ExprId.new(13) : nil
  WholeUnionCallNode.new(span, callee, args, block_id, named).kind
end

class IndirectCallNodeFactory
  def backend_class
    Adamas::Compiler::Frontend::CallNode
  end

  def validate(live : Bool) : Nil
    span = Adamas::Compiler::Frontend::Span.zero
    callee = Adamas::Compiler::Frontend::ExprId.new(3)
    args = [Adamas::Compiler::Frontend::ExprId.new(5)]
    named = [Adamas::Compiler::Frontend::NamedArgument.new("param".to_slice, Adamas::Compiler::Frontend::ExprId.new(7), span, span)]
    backend_class.new(span, callee, args)
    backend_class.new(span, callee, args, Adamas::Compiler::Frontend::ExprId.new(11))
    block_id = live ? Adamas::Compiler::Frontend::ExprId.new(13) : nil
    node = backend_class.new(span, callee, args, block_id, named)
    LibC.exit(95) if node.has_block? != live
    if block_value = node.block
      LibC.exit(96) unless block_value.index == 13
    end
    actual = node.named_args
    LibC.exit(97) unless actual && actual.size == 1 && actual[0].value.index == 7
  end
end

validate_call_node(false)
validate_call_node(true)
puts "both CallNode overloads ok"
puts validate_whole_union_call_node(false)
puts validate_whole_union_call_node(true)
factory = IndirectCallNodeFactory.new
factory.validate(false)
factory.validate(true)
puts "indirect CallNode overloads ok"
