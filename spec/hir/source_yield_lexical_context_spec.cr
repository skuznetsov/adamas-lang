require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_register_source_yield_owner(
    name : String,
    source_def : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    @function_defs[name] = source_def
    set_function_def_arena(name, source_arena)
  end

  def __test_exact_source_arena_for_yield_owner(
    source_def : Adamas::Compiler::Frontend::DefNode,
    preferred_arena : Adamas::Compiler::Frontend::ArenaLike?,
  ) : Adamas::Compiler::Frontend::ArenaLike?
    exact_source_arena_for_yield_owner(source_def, preferred_arena)
  end

  def __test_recover_source_yield_owner(
    source_def : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::Compiler::Frontend::DefNode?
    source_recovered_def_for(source_def, arena)
  end

  def __test_arena_fits_source_yield_owner?(
    arena : Adamas::Compiler::Frontend::ArenaLike,
    source_def : Adamas::Compiler::Frontend::DefNode,
  ) : Bool
    arena_fits_def?(arena, source_def)
  end

  def __test_source_yield_context : SourceYieldContext
    @source_yield_context
  end

  def __test_method_source_yield_context(
    source_def : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : SourceYieldContext
    method_source_yield_context(source_def, arena)
  end

  def __test_captured_block_source_yield_context(
    source_def : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : SourceYieldContext?
    captured_block_source_yield_context(source_def, arena)
  end

  def __test_source_yield_inline_stack_state
    {
      __test_yield_stack_identity(@inline_yield_block_stack),
      __test_yield_stack_identity(@inline_yield_block_arena_stack),
      __test_yield_stack_identity(@inline_yield_block_param_types_stack),
      __test_yield_stack_identity(@inline_yield_block_return_stack),
      __test_yield_stack_identity(@inline_yield_name_stack),
    }
  end

  def __test_seed_source_yield_inline_stack(
    block : Adamas::Compiler::Frontend::BlockNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    @inline_yield_block_stack << block
    @inline_yield_block_arena_stack << arena
    @inline_yield_block_param_types_stack << nil
    @inline_yield_block_return_stack << nil
    @inline_yield_name_stack << "outer-inline-owner"
  end

  def __test_dispatch_proc_yield_with_inline_owner(
    ctx : LoweringContext,
    node : Adamas::Compiler::Frontend::YieldNode,
    source_def : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
    block : Adamas::Compiler::Frontend::BlockNode,
  ) : ValueId
    saved_source_yield_context = @source_yield_context
    @source_yield_context = proc_literal_source_yield_context(method_source_yield_context(source_def, source_arena))
    @inline_yield_block_stack << block
    @inline_yield_block_arena_stack << source_arena
    @inline_yield_block_param_types_stack << nil
    @inline_yield_block_return_stack << nil
    @inline_yield_name_stack << "outer-inline-owner"
    begin
      lower_node(ctx, node)
    ensure
      @inline_yield_block_stack.pop?
      @inline_yield_block_arena_stack.pop?
      @inline_yield_block_param_types_stack.pop?
      @inline_yield_block_return_stack.pop?
      @inline_yield_name_stack.pop?
      @source_yield_context = saved_source_yield_context
    end
  end

  def __test_lower_proc_literal_for_yield_owner(
    ctx : LoweringContext,
    node : Adamas::Compiler::Frontend::ProcLiteralNode,
    source_def : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : ValueId
    saved_source_yield_context = @source_yield_context
    @source_yield_context = method_source_yield_context(source_def, source_arena)
    begin
      lower_proc_literal(ctx, node)
    ensure
      @source_yield_context = saved_source_yield_context
    end
  end

  private def __test_yield_stack_identity(stack : Array(T)) : Tuple(UInt64, Int32, String) forall T
    {stack.object_id.to_u64, stack.size, stack.inspect}
  end
end

private def parse_source_yield_context_program(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  {program, source}
end

private def source_yield_context_converter(program, source : String) : Adamas::HIR::AstToHir
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter
end

private def source_yield_context_def(program, name : String) : Adamas::Compiler::Frontend::DefNode
  program.roots.compact_map do |id|
    node = program.arena[id].as?(Adamas::Compiler::Frontend::DefNode)
    node if node && String.new(node.name) == name
  end.first.not_nil!
end

private def source_yield_context_proc_and_block(
  program,
  source_def : Adamas::Compiler::Frontend::DefNode,
) : {Adamas::Compiler::Frontend::ProcLiteralNode, Adamas::Compiler::Frontend::YieldNode, Adamas::Compiler::Frontend::BlockNode}
  arena = program.arena
  proc_node = arena[source_def.body.not_nil!.first].as(Adamas::Compiler::Frontend::ProcLiteralNode)
  yield_node = arena[proc_node.body.first].as(Adamas::Compiler::Frontend::YieldNode)
  call_node = program.roots.compact_map do |id|
    arena[id].as?(Adamas::Compiler::Frontend::CallNode)
  end.last.not_nil!
  block_node = arena[call_node.block.not_nil!].as(Adamas::Compiler::Frontend::BlockNode)
  {proc_node, yield_node, block_node}
end

private def assert_top_level_source_yield_context(
  converter : Adamas::HIR::AstToHir,
  arena : Adamas::Compiler::Frontend::ArenaLike,
) : Nil
  context = converter.__test_source_yield_context
  context.kind.should eq(Adamas::HIR::AstToHir::SourceYieldContextKind::TopLevel)
  context.source_def.should be_nil
  context.source_arena.not_nil!.same?(arena).should be_true
end

describe "source lexical yield context ownership" do
  it "uses a registered source owner over a same-shape preferred arena" do
    source = <<-CRYSTAL
      def owner(argument : Int32)
        65
      end
    CRYSTAL
    foreign_source = source.gsub("65", "66")
    program, source = parse_source_yield_context_program(source)
    foreign_program, foreign_source = parse_source_yield_context_program(foreign_source)
    source_arena = program.arena
    foreign_arena = foreign_program.arena
    source_def = source_yield_context_def(program, "owner")
    foreign_def = source_yield_context_def(foreign_program, "owner")

    source_def.span.should eq(foreign_def.span)
    source_arena.size.should eq(foreign_arena.size)
    source_def.body.not_nil!.first.index.should eq(foreign_def.body.not_nil!.first.index)
    source_arena[source_def.body.not_nil!.first].as(Adamas::Compiler::Frontend::NumberNode).parsed_int.should eq(65_i64)
    foreign_arena[foreign_def.body.not_nil!.first].as(Adamas::Compiler::Frontend::NumberNode).parsed_int.should eq(66_i64)
    converter = Adamas::HIR::AstToHir.new(
      foreign_arena,
      sources_by_arena: {
        source_arena.object_id.to_u64   => source,
        foreign_arena.object_id.to_u64 => foreign_source,
      },
      main_arenas: [foreign_arena, source_arena],
    )
    converter.no_prelude = true
    converter.__test_register_source_yield_owner("owner", source_def, source_arena)
    source_def.params.not_nil!.clear
    recovered = converter.__test_recover_source_yield_owner(source_def, source_arena).not_nil!
    recovered.same?(source_def).should be_false
    recovered.body.not_nil!.same?(source_def.body.not_nil!).should be_true
    converter.__test_arena_fits_source_yield_owner?(source_arena, recovered).should be_true
    converter.__test_arena_fits_source_yield_owner?(foreign_arena, recovered).should be_true

    converter.__test_exact_source_arena_for_yield_owner(recovered, foreign_arena)
      .not_nil!.same?(source_arena).should be_true
    context = converter.__test_method_source_yield_context(recovered, foreign_arena)
    context.source_def.not_nil!.same?(recovered).should be_true
    context.source_arena.not_nil!.same?(source_arena).should be_true
  end

  it "retains the exact selected Def and arena for methods and captured blocks" do
    source = <<-CRYSTAL
      def stored_block(&callback : -> Int32)
        callback
      end

      def yield_only(&callback : -> Int32)
        yield
      end
    CRYSTAL
    program, source = parse_source_yield_context_program(source)
    arena = program.arena
    converter = source_yield_context_converter(program, source)
    stored = source_yield_context_def(program, "stored_block")
    yielding = source_yield_context_def(program, "yield_only")

    method_context = converter.__test_method_source_yield_context(yielding, arena)
    method_context.kind.should eq(Adamas::HIR::AstToHir::SourceYieldContextKind::Method)
    method_context.source_def.not_nil!.same?(yielding).should be_true
    method_context.source_arena.not_nil!.same?(arena).should be_true

    captured_context = converter.__test_captured_block_source_yield_context(stored, arena).not_nil!
    captured_context.kind.should eq(Adamas::HIR::AstToHir::SourceYieldContextKind::CapturedBlock)
    captured_context.source_def.not_nil!.same?(stored).should be_true
    captured_context.source_arena.not_nil!.same?(arena).should be_true
    converter.__test_captured_block_source_yield_context(yielding, arena).should be_nil
  end

  it "restores the top-level source owner after nested Def lowering" do
    source = <<-CRYSTAL
      def helper
        65
      end
    CRYSTAL
    program, source = parse_source_yield_context_program(source)
    arena = program.arena
    converter = source_yield_context_converter(program, source)
    converter.lower_def(source_yield_context_def(program, "helper"))
    assert_top_level_source_yield_context(converter, arena)
  end

  it "rejects Proc yield before inline substitution or argument lowering" do
    source = <<-CRYSTAL
      def capture_yield_proc(&callback : -> Int32)
        -> { yield missing_yield_argument }
      end

      capture_yield_proc { 65 }
    CRYSTAL
    program, source = parse_source_yield_context_program(source)
    arena = program.arena
    converter = source_yield_context_converter(program, source)
    source_def = source_yield_context_def(program, "capture_yield_proc")
    _, yield_node, block_node = source_yield_context_proc_and_block(program, source_def)
    function = converter.module.create_function("source_yield_dispatch_probe", Adamas::HIR::TypeRef::VOID)
    ctx = Adamas::HIR::LoweringContext.new(function, converter.module, arena)
    inline_stacks_before = converter.__test_source_yield_inline_stack_state

    expect_raises(Adamas::HIR::LoweringError, /can't use `yield` inside a proc literal or captured block/) do
      converter.__test_dispatch_proc_yield_with_inline_owner(
        ctx,
        yield_node,
        source_def,
        arena,
        block_node,
      )
    end
    converter.__test_source_yield_inline_stack_state.should eq(inline_stacks_before)
    assert_top_level_source_yield_context(converter, arena)
  end

  it "restores each inline-yield stack identity when Proc body lowering raises" do
    source = <<-CRYSTAL
      def capture_yield_proc(&callback : -> Int32)
        -> { yield missing_yield_argument }
      end

      capture_yield_proc { 65 }
    CRYSTAL
    program, source = parse_source_yield_context_program(source)
    arena = program.arena
    converter = source_yield_context_converter(program, source)
    source_def = source_yield_context_def(program, "capture_yield_proc")
    proc_node, _, block_node = source_yield_context_proc_and_block(program, source_def)
    function = converter.module.create_function("source_yield_proc_probe", Adamas::HIR::TypeRef::VOID)
    ctx = Adamas::HIR::LoweringContext.new(function, converter.module, arena)

    converter.__test_seed_source_yield_inline_stack(block_node, arena)
    inline_stacks_before = converter.__test_source_yield_inline_stack_state
    expect_raises(Adamas::HIR::LoweringError, /can't use `yield` inside a proc literal or captured block/) do
      converter.__test_lower_proc_literal_for_yield_owner(ctx, proc_node, source_def, arena)
    end
    converter.__test_source_yield_inline_stack_state.should eq(inline_stacks_before)
    assert_top_level_source_yield_context(converter, arena)
  end
end
