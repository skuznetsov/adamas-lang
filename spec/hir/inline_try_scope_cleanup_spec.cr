require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::LoweringContext
  def __test_scope_state : Array(Int32)
    [
      @scope_stack.size,
      @locals_snapshots.size,
      @debug_local_snapshots.size,
      @boxed_locals_snapshots.size,
      @block_parameter_binding_snapshots.size,
    ]
  end
end

class Adamas::HIR::AstToHir
  def __test_nullable_scope_type(type : Adamas::HIR::TypeRef) : Adamas::HIR::TypeRef
    create_union_type_for_nullable(type)
  end

  def __test_inline_try_block_core(
    ctx : Adamas::HIR::LoweringContext,
    receiver_id : Adamas::HIR::ValueId,
    receiver_type : Adamas::HIR::TypeRef,
    block : Adamas::Compiler::Frontend::BlockNode,
  ) : Adamas::HIR::ValueId
    inline_try_block_core(ctx, receiver_id, receiver_type, block)
  end

  def __test_inline_try_proc_core(
    ctx : Adamas::HIR::LoweringContext,
    receiver_id : Adamas::HIR::ValueId,
    receiver_type : Adamas::HIR::TypeRef,
    proc_node : Adamas::Compiler::Frontend::ProcLiteralNode,
  ) : Adamas::HIR::ValueId
    inline_try_proc_core(ctx, receiver_id, receiver_type, proc_node)
  end

end

private record InlineTryScopeProbe,
  converter : Adamas::HIR::AstToHir,
  context : Adamas::HIR::LoweringContext,
  function : Adamas::HIR::Function,
  arena : Adamas::Compiler::Frontend::ArenaLike,
  roots : Array(Adamas::Compiler::Frontend::ExprId)

private def inline_try_scope_converter(source : String) : InlineTryScopeProbe
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  function = converter.module.create_function("__inline_try_scope_probe", Adamas::HIR::TypeRef::VOID)
  context = Adamas::HIR::LoweringContext.new(function, converter.module, arena)
  InlineTryScopeProbe.new(converter, context, function, arena, program.roots)
end

private def inline_try_block_node(probe : InlineTryScopeProbe) : Adamas::Compiler::Frontend::BlockNode
  call = probe.arena[probe.roots.first].as(Adamas::Compiler::Frontend::CallNode)
  probe.arena[call.block.not_nil!].as(Adamas::Compiler::Frontend::BlockNode)
end

private def inline_try_proc_node(probe : InlineTryScopeProbe) : Adamas::Compiler::Frontend::ProcLiteralNode
  probe.arena[probe.roots.first].as(Adamas::Compiler::Frontend::ProcLiteralNode)
end

private def inline_try_scope_receiver(probe : InlineTryScopeProbe) : {Adamas::HIR::ValueId, Adamas::HIR::TypeRef}
  nullable_type = probe.converter.__test_nullable_scope_type(Adamas::HIR::TypeRef::INT32)
  receiver = probe.function.add_param("receiver", nullable_type)
  probe.context.register_type(receiver.id, nullable_type)
  {receiver.id, nullable_type}
end

private def inline_try_scope_parent_state(probe : InlineTryScopeProbe) : {Adamas::HIR::ScopeId, Array(Int32)}
  probe.context.push_scope(Adamas::HIR::ScopeKind::Block)
  closure_scope = probe.context.push_scope(Adamas::HIR::ScopeKind::Closure)
  {closure_scope, probe.context.__test_scope_state}
end

describe "inline try exception cleanup" do
  it "unwinds its owned block scope and restores receiver narrowing on a source error" do
    probe = inline_try_scope_converter("receiver.try { |value| MissingInlineTryScopeConstant }")
    receiver_id, receiver_type = inline_try_scope_receiver(probe)
    expected_scope, expected_scope_state = inline_try_scope_parent_state(probe)

    error = nil.as(Adamas::HIR::LoweringError?)
    begin
      probe.converter.__test_inline_try_block_core(
        probe.context, receiver_id, receiver_type, inline_try_block_node(probe),
      )
    rescue caught : Adamas::HIR::LoweringError
      error = caught
    end

    error.should_not be_nil
    error.not_nil!.message.not_nil!.should eq("undefined constant MissingInlineTryScopeConstant")
    error.not_nil!.node.should_not be_nil
    probe.context.current_scope.should eq(expected_scope)
    probe.context.__test_scope_state.should eq(expected_scope_state)
    probe.context.type_of(receiver_id).should eq(receiver_type)
  end

  it "unwinds its owned proc scope and restores receiver narrowing on a source error" do
    probe = inline_try_scope_converter("->(value : Int32) { MissingInlineTryScopeConstant }")
    receiver_id, receiver_type = inline_try_scope_receiver(probe)
    expected_scope, expected_scope_state = inline_try_scope_parent_state(probe)

    error = nil.as(Adamas::HIR::LoweringError?)
    begin
      probe.converter.__test_inline_try_proc_core(
        probe.context, receiver_id, receiver_type, inline_try_proc_node(probe),
      )
    rescue caught : Adamas::HIR::LoweringError
      error = caught
    end

    error.should_not be_nil
    error.not_nil!.message.not_nil!.should eq("undefined constant MissingInlineTryScopeConstant")
    error.not_nil!.node.should_not be_nil
    probe.context.current_scope.should eq(expected_scope)
    probe.context.__test_scope_state.should eq(expected_scope_state)
    probe.context.type_of(receiver_id).should eq(receiver_type)
  end


  it "balances a successful inline try block and preserves its nullable result" do
    probe = inline_try_scope_converter("receiver.try { |value| value }")
    receiver_id, receiver_type = inline_try_scope_receiver(probe)
    expected_scope, expected_scope_state = inline_try_scope_parent_state(probe)
    value_id = probe.converter.__test_inline_try_block_core(
      probe.context, receiver_id, receiver_type, inline_try_block_node(probe),
    )
    probe.context.current_scope.should eq(expected_scope)
    probe.context.__test_scope_state.should eq(expected_scope_state)
    probe.context.type_of(receiver_id).should eq(receiver_type)
    probe.context.type_of(value_id).should eq(receiver_type)
  end

  it "balances a successful inline try proc and preserves its nullable result" do
    probe = inline_try_scope_converter("->(value : Int32) { value }")
    receiver_id, receiver_type = inline_try_scope_receiver(probe)
    expected_scope, expected_scope_state = inline_try_scope_parent_state(probe)
    value_id = probe.converter.__test_inline_try_proc_core(
      probe.context, receiver_id, receiver_type, inline_try_proc_node(probe),
    )
    probe.context.current_scope.should eq(expected_scope)
    probe.context.__test_scope_state.should eq(expected_scope_state)
    probe.context.type_of(receiver_id).should eq(receiver_type)
    probe.context.type_of(value_id).should eq(receiver_type)
  end
end


describe "conditional scopes inside inline try" do
  {
    "static true" => "if true; MissingInlineTryScopeConstant; else; 1; end",
    "static false" => "if false; 1; else; MissingInlineTryScopeConstant; end",
    "static nil" => "if nil; 1; else; MissingInlineTryScopeConstant; end",
    "static is_a" => "if value.is_a?(Int32); MissingInlineTryScopeConstant; else; 1; end",
    "dynamic then" => "if flag; MissingInlineTryScopeConstant; else; 1; end",
    "dynamic elsif" => "if flag; 1; elsif flag; MissingInlineTryScopeConstant; else; 2; end",
    "dynamic else" => "if flag; 1; else; MissingInlineTryScopeConstant; end",
  }.each do |label, body|
    {false, true}.each do |proc_body|
      it "restores exact caller scope and receiver after #{label} in #{proc_body ? "Proc" : "block"}" do
        source = proc_body ? "->(value : Int32) { #{body} }" : "receiver.try { |value| #{body} }"
        probe = inline_try_scope_converter(source)
        receiver_id, receiver_type = inline_try_scope_receiver(probe)
        flag = probe.function.add_param("flag", Adamas::HIR::TypeRef::BOOL)
        probe.context.register_local("flag", flag.id)
        probe.context.register_type(flag.id, Adamas::HIR::TypeRef::BOOL)
        expected_scope, expected_state = inline_try_scope_parent_state(probe)
        error = nil.as(Adamas::HIR::LoweringError?)
        begin
          if proc_body
            probe.converter.__test_inline_try_proc_core(
              probe.context, receiver_id, receiver_type, inline_try_proc_node(probe))
          else
            probe.converter.__test_inline_try_block_core(
              probe.context, receiver_id, receiver_type, inline_try_block_node(probe))
          end
        rescue caught : Adamas::HIR::LoweringError
          error = caught
        end
        error.should_not be_nil
        error.not_nil!.message.should eq("undefined constant MissingInlineTryScopeConstant")
        error.not_nil!.node.should_not be_nil
        probe.context.current_scope.should eq(expected_scope)
        probe.context.__test_scope_state.should eq(expected_state)
        probe.context.type_of(receiver_id).should eq(receiver_type)
      end
    end
  end
end
