require "../src/compiler/frontend/ast"

class IncompleteCallNode
  def initialize(span : Adamas::Compiler::Frontend::Span, callee : Adamas::Compiler::Frontend::ExprId, args : Array(Adamas::Compiler::Frontend::ExprId))
  end

  def initialize(span : Adamas::Compiler::Frontend::Span, callee : Adamas::Compiler::Frontend::ExprId, args : Array(Adamas::Compiler::Frontend::ExprId), block : Adamas::Compiler::Frontend::ExprId, named : Array(Adamas::Compiler::Frontend::NamedArgument))
  end
end

span = Adamas::Compiler::Frontend::Span.zero
callee = Adamas::Compiler::Frontend::ExprId.new(3)
args = [Adamas::Compiler::Frontend::ExprId.new(5)]
named = [Adamas::Compiler::Frontend::NamedArgument.new("param".to_slice, Adamas::Compiler::Frontend::ExprId.new(7), span, span)]
block_id = ARGV.size > 0 ? Adamas::Compiler::Frontend::ExprId.new(13) : nil
IncompleteCallNode.new(span, callee, args, block_id, named)
