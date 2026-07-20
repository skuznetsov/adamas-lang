require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_node_for_call_expr(
    call_arena : Adamas::Compiler::Frontend::ArenaLike,
    expr_id : Adamas::Compiler::Frontend::ExprId,
  ) : Adamas::Compiler::Frontend::Node?
    node_for_call_expr(call_arena, expr_id)
  end

  def __test_build_block_from_block_pass(
    call_arena : Adamas::Compiler::Frontend::ArenaLike,
    ambient_arena : Adamas::Compiler::Frontend::ArenaLike,
    proc_expr : Adamas::Compiler::Frontend::ExprId,
  ) : Adamas::Compiler::Frontend::BlockNode?
    saved_arena = @arena
    self.arena = ambient_arena
    begin
      build_block_from_block_pass(call_arena, proc_expr, nil, Adamas::Compiler::Frontend::Span.zero)
    ensure
      self.arena = saved_arena
    end
  end

  def __test_lower_call_with_exact_arena(
    arena : Adamas::Compiler::Frontend::ArenaLike,
    node : Adamas::Compiler::Frontend::CallNode,
  ) : Adamas::HIR::ValueId
    self.arena = arena
    function = @module.create_function("__test_lower_call_exact_arena", Adamas::HIR::TypeRef::NIL)
    ctx = Adamas::HIR::LoweringContext.new(function, @module, arena)
    lower_call(ctx, node)
  end
end

describe Adamas::HIR::AstToHir do
  describe "call child arena ownership" do
    it "fails closed when a plain call arena lacks a foreign block id" do
      owner_arena = Adamas::Compiler::Frontend::AstArena.new
      foreign_arena = Adamas::Compiler::Frontend::AstArena.new
      block_id = foreign_arena.add_typed(
        Adamas::Compiler::Frontend::BlockNode.new(
          Adamas::Compiler::Frontend::Span.zero,
          nil,
          [] of Adamas::Compiler::Frontend::ExprId,
        )
      )
      converter = Adamas::HIR::AstToHir.new(foreign_arena)

      converter.__test_node_for_call_expr(owner_arena, block_id).should be_nil
    end

    it "fails closed instead of raising for a generated id owned by another canonical view" do
      source_owner = Adamas::Compiler::Frontend::AstArena.new
      view_a = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      view_b = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      foreign_id = view_b.add(
        Adamas::Compiler::Frontend::BlockNode.new(
          Adamas::Compiler::Frontend::Span.zero,
          nil,
          [] of Adamas::Compiler::Frontend::ExprId,
        )
      )
      converter = Adamas::HIR::AstToHir.new(view_a)

      converter.__test_node_for_call_expr(view_a, foreign_id).should be_nil
    end

    it "returns a block from the exact call arena" do
      owner_arena = Adamas::Compiler::Frontend::AstArena.new
      foreign_arena = Adamas::Compiler::Frontend::AstArena.new
      block_id = owner_arena.add_typed(
        Adamas::Compiler::Frontend::BlockNode.new(
          Adamas::Compiler::Frontend::Span.zero,
          nil,
          [] of Adamas::Compiler::Frontend::ExprId,
        )
      )
      converter = Adamas::HIR::AstToHir.new(foreign_arena)

      resolved = converter.__test_node_for_call_expr(owner_arena, block_id)
      resolved.should_not be_nil
      resolved.not_nil!.same?(owner_arena[block_id]).should be_true
    end

    it "does not synthesize a block from a foreign ambient block-pass id" do
      owner_arena = Adamas::Compiler::Frontend::AstArena.new
      ambient_arena = Adamas::Compiler::Frontend::AstArena.new
      proc_id = ambient_arena.add_typed(
        Adamas::Compiler::Frontend::ProcLiteralNode.new(
          Adamas::Compiler::Frontend::Span.zero,
          nil,
          nil,
          [] of Adamas::Compiler::Frontend::ExprId,
        )
      )
      converter = Adamas::HIR::AstToHir.new(ambient_arena)

      converter.__test_build_block_from_block_pass(owner_arena, ambient_arena, proc_id).should be_nil
    end

    it "fails closed instead of raising for a foreign generated block-pass id" do
      source_owner = Adamas::Compiler::Frontend::AstArena.new
      view_a = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      view_b = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      foreign_id = view_b.add(
        Adamas::Compiler::Frontend::ProcLiteralNode.new(
          Adamas::Compiler::Frontend::Span.zero,
          nil,
          nil,
          [] of Adamas::Compiler::Frontend::ExprId,
        )
      )
      converter = Adamas::HIR::AstToHir.new(view_a)

      converter.__test_build_block_from_block_pass(view_a, view_a, foreign_id).should be_nil
    end

    it "rejects an invalid trailing block-pass operand before ordinary argument lowering" do
      arena = Adamas::Compiler::Frontend::AstArena.new
      span = Adamas::Compiler::Frontend::Span.zero
      callee = arena.add_typed(
        Adamas::Compiler::Frontend::IdentifierNode.new(span, "noop".to_slice)
      )
      trailing_amp = arena.add_typed(
        Adamas::Compiler::Frontend::UnaryNode.new(span, "&".to_slice, Adamas::Compiler::Frontend::ExprId.new(999))
      )
      call = arena.add_typed(
        Adamas::Compiler::Frontend::CallNode.new(span, callee, [trailing_amp])
      )
      converter = Adamas::HIR::AstToHir.new(arena)

      expect_raises(Adamas::HIR::LoweringError, /call block-pass operand is not owned by call arena/) do
        converter.__test_lower_call_with_exact_arena(arena, arena[call].as(Adamas::Compiler::Frontend::CallNode))
      end
    end

    it "rejects a foreign generated trailing block-pass operand before recovery" do
      source_owner = Adamas::Compiler::Frontend::AstArena.new
      view_a = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      view_b = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      span = Adamas::Compiler::Frontend::Span.zero
      callee = view_a.add(
        Adamas::Compiler::Frontend::IdentifierNode.new(span, "noop".to_slice)
      )
      foreign_operand = view_b.add(
        Adamas::Compiler::Frontend::IdentifierNode.new(span, "foreign_proc".to_slice)
      )
      trailing_amp = view_a.add(
        Adamas::Compiler::Frontend::UnaryNode.new(span, "&".to_slice, foreign_operand)
      )
      call = view_a.add(
        Adamas::Compiler::Frontend::CallNode.new(span, callee, [trailing_amp])
      )
      converter = Adamas::HIR::AstToHir.new(view_a, main_arenas: [view_a, view_b])

      expect_raises(Adamas::HIR::LoweringError, /call block-pass operand is not owned by call arena/) do
        converter.__test_lower_call_with_exact_arena(view_a, view_a[call].as(Adamas::Compiler::Frontend::CallNode))
      end
    end

    it "rejects a foreign canonical trailing block before global recovery" do
      source_owner = Adamas::Compiler::Frontend::AstArena.new
      view_a = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      view_b = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      span = Adamas::Compiler::Frontend::Span.zero
      callee = view_a.add(
        Adamas::Compiler::Frontend::IdentifierNode.new(span, "noop".to_slice)
      )
      foreign_block = view_b.add(
        Adamas::Compiler::Frontend::BlockNode.new(
          span,
          nil,
          [] of Adamas::Compiler::Frontend::ExprId,
        )
      )
      call = view_a.add(
        Adamas::Compiler::Frontend::CallNode.new(span, callee, [foreign_block])
      )
      converter = Adamas::HIR::AstToHir.new(view_a, main_arenas: [view_a, view_b])

      expect_raises(Adamas::HIR::LoweringError, /call trailing expression is not owned by call arena/) do
        converter.__test_lower_call_with_exact_arena(view_a, view_a[call].as(Adamas::Compiler::Frontend::CallNode))
      end
    end

    it "rejects a wholly foreign canonical trailing block-pass unary before recovery" do
      source_owner = Adamas::Compiler::Frontend::AstArena.new
      view_a = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      view_b = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      span = Adamas::Compiler::Frontend::Span.zero
      callee = view_a.add(
        Adamas::Compiler::Frontend::IdentifierNode.new(span, "noop".to_slice)
      )
      foreign_proc = view_b.add(
        Adamas::Compiler::Frontend::IdentifierNode.new(span, "foreign_proc".to_slice)
      )
      foreign_unary = view_b.add(
        Adamas::Compiler::Frontend::UnaryNode.new(span, "&".to_slice, foreign_proc)
      )
      call = view_a.add(
        Adamas::Compiler::Frontend::CallNode.new(span, callee, [foreign_unary])
      )
      converter = Adamas::HIR::AstToHir.new(view_a, main_arenas: [view_a, view_b])

      expect_raises(Adamas::HIR::LoweringError, /call trailing expression is not owned by call arena/) do
        converter.__test_lower_call_with_exact_arena(view_a, view_a[call].as(Adamas::Compiler::Frontend::CallNode))
      end
    end

    it "rejects an invalid direct block expression before call resolution" do
      arena = Adamas::Compiler::Frontend::AstArena.new
      span = Adamas::Compiler::Frontend::Span.zero
      callee = arena.add_typed(
        Adamas::Compiler::Frontend::IdentifierNode.new(span, "noop".to_slice)
      )
      call = arena.add_typed(
        Adamas::Compiler::Frontend::CallNode.new(
          span,
          callee,
          [] of Adamas::Compiler::Frontend::ExprId,
          Adamas::Compiler::Frontend::ExprId.new(999),
        )
      )
      converter = Adamas::HIR::AstToHir.new(arena)

      expect_raises(Adamas::HIR::LoweringError, /call block expression is not owned by call arena/) do
        converter.__test_lower_call_with_exact_arena(arena, arena[call].as(Adamas::Compiler::Frontend::CallNode))
      end
    end

    it "rejects a foreign generated direct block before call resolution" do
      source_owner = Adamas::Compiler::Frontend::AstArena.new
      view_a = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      view_b = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
        source_owner,
        0,
        0,
        parsed_limit: 0,
      )
      span = Adamas::Compiler::Frontend::Span.zero
      callee = view_a.add(
        Adamas::Compiler::Frontend::IdentifierNode.new(span, "noop".to_slice)
      )
      foreign_block = view_b.add(
        Adamas::Compiler::Frontend::BlockNode.new(
          span,
          nil,
          [] of Adamas::Compiler::Frontend::ExprId,
        )
      )
      call = view_a.add(
        Adamas::Compiler::Frontend::CallNode.new(
          span,
          callee,
          [] of Adamas::Compiler::Frontend::ExprId,
          foreign_block,
        )
      )
      converter = Adamas::HIR::AstToHir.new(view_a, main_arenas: [view_a, view_b])

      expect_raises(Adamas::HIR::LoweringError, /call block expression is not owned by call arena/) do
        converter.__test_lower_call_with_exact_arena(view_a, view_a[call].as(Adamas::Compiler::Frontend::CallNode))
      end
    end

    it "rejects a malformed direct block before type-like fast return" do
      arena = Adamas::Compiler::Frontend::AstArena.new
      span = Adamas::Compiler::Frontend::Span.zero
      callee = arena.add_typed(
        Adamas::Compiler::Frontend::IdentifierNode.new(span, "Array".to_slice)
      )
      call = arena.add_typed(
        Adamas::Compiler::Frontend::CallNode.new(
          span,
          callee,
          [] of Adamas::Compiler::Frontend::ExprId,
          Adamas::Compiler::Frontend::ExprId.new(999),
        )
      )
      converter = Adamas::HIR::AstToHir.new(arena)

      expect_raises(Adamas::HIR::LoweringError, /call block expression is not owned by call arena/) do
        converter.__test_lower_call_with_exact_arena(arena, arena[call].as(Adamas::Compiler::Frontend::CallNode))
      end
    end

    it "rejects a malformed trailing block-pass before is_a? fast return" do
      arena = Adamas::Compiler::Frontend::AstArena.new
      span = Adamas::Compiler::Frontend::Span.zero
      callee = arena.add_typed(
        Adamas::Compiler::Frontend::IdentifierNode.new(span, "is_a?".to_slice)
      )
      type_arg = arena.add_typed(
        Adamas::Compiler::Frontend::IdentifierNode.new(span, "Int32".to_slice)
      )
      trailing_amp = arena.add_typed(
        Adamas::Compiler::Frontend::UnaryNode.new(span, "&".to_slice, Adamas::Compiler::Frontend::ExprId.new(999))
      )
      call = arena.add_typed(
        Adamas::Compiler::Frontend::CallNode.new(
          span,
          callee,
          [type_arg, trailing_amp],
        )
      )
      converter = Adamas::HIR::AstToHir.new(arena)

      expect_raises(Adamas::HIR::LoweringError, /call block-pass operand is not owned by call arena/) do
        converter.__test_lower_call_with_exact_arena(arena, arena[call].as(Adamas::Compiler::Frontend::CallNode))
      end
    end

    it "keeps call-owned block readers owner-scoped" do
      source = File.read(File.expand_path("../../src/compiler/hir/ast_to_hir.cr", __DIR__))

      helper = source.match(/private\s+def\s+node_for_call_expr\b([\s\S]*?)(?=\n\s*private\s+def\s+)/)
      helper.should_not be_nil
      helper.not_nil![1].should_not match(/\bnode_for_expr\s*\(/)

      trailing_recovery = source.match(/call_args\s*=\s*node\.args([\s\S]*?)block_expr_index\s*=/)
      trailing_recovery.should_not be_nil
      trailing_recovery.not_nil![1].should_not match(/\bnode_for_expr\s*\(/)

      inline_yield = source.match(/Handle\s+yield-functions\s+with\s+inline\s+expansion\s+FIRST([\s\S]*?)elsif\s+block_pass_expr/)
      inline_yield.should_not be_nil
      inline_yield.not_nil![1].should_not match(/\bnode_for_expr\s*\(/)
    end

    it "keeps lower_call block classification readers owner-scoped" do
      source = File.read(File.expand_path("../../src/compiler/hir/ast_to_hir.cr", __DIR__))
      lower_call = source.match(/private\s+def\s+lower_call\b([\s\S]*?)(?=\n\s*private\s+def\s+)/)
      lower_call.should_not be_nil
      lower_call_body = lower_call.not_nil![1]
      lower_call_body.should_not match(/\b(?:blk_node|block_pass_node|operand_node)\s*=\s*@arena\s*\[/)
      lower_call_body.should_not match(/@arena\s*\[\s*(?:block_expr|blk_expr|block_pass_expr|operand)\s*\]/)
    end

    it "rejects malformed trailing amp operands before truncating call_args" do
      source = File.read(File.expand_path("../../src/compiler/hir/ast_to_hir.cr", __DIR__))
      lower_call = source.match(/private\s+def\s+lower_call\b([\s\S]*?)(?=\n\s*private\s+def\s+)/)
      lower_call.should_not be_nil
      trailing_branch = lower_call.not_nil![1].match(/when\s+Adamas::Compiler::Frontend::UnaryNode([\s\S]*?)block_expr_index\s*=/)
      trailing_branch.should_not be_nil
      branch = trailing_branch.not_nil![1]
      branch.should match(/operand_node\s*=\s*node_for_call_expr\(\s*call_arena\s*,\s*operand\s*\)/)
      branch.should match(/raise\s+(?:Adamas::HIR::)?LoweringError\.new\(\s*"call block-pass operand is not owned by call arena"\s*\)/)
      branch.should match(/operand_node\s*=\s*node_for_call_expr\([\s\S]*raise\s+(?:Adamas::HIR::)?LoweringError\.new[\s\S]*trace_lower_call_arena_expr[\s\S]*call_args\s*=\s*call_args\[0\.\.\.-1\]/)
    end

    it "admits every trailing expression before ordinary argument lowering" do
      source = File.read(File.expand_path("../../src/compiler/hir/ast_to_hir.cr", __DIR__))
      lower_call = source.match(/private\s+def\s+lower_call\b([\s\S]*?)(?=\n\s*private\s+def\s+)/)
      lower_call.should_not be_nil
      admission = lower_call.not_nil![1].match(/last_node\s*=\s*node_for_call_expr\(\s*call_arena\s*,\s*last_id\s*\)([\s\S]*?)case\s+last_node/)
      admission.should_not be_nil
      body = admission.not_nil![1]
      body.should match(/unless\s+last_node/)
      body.should match(/raise\s+(?:Adamas::HIR::)?LoweringError\.new\(\s*"call trailing expression is not owned by call arena"\s*\)/)
    end

    it "validates direct node.block ownership before block flags" do
      source = File.read(File.expand_path("../../src/compiler/hir/ast_to_hir.cr", __DIR__))
      lower_call = source.match(/private\s+def\s+lower_call\b([\s\S]*?)(?=\n\s*private\s+def\s+)/)
      lower_call.should_not be_nil
      direct_block = lower_call.not_nil![1].match(/block_expr\s*=\s*node\.block([\s\S]*?)block_expr_index\s*=/)
      direct_block.should_not be_nil
      direct_block.not_nil![1].should match(/node_for_call_expr\(\s*call_arena\s*,\s*block_expr\s*\)/)
      direct_block.not_nil![1].should match(/raise\s+(?:Adamas::HIR::)?LoweringError\.new\(\s*"call block expression is not owned by call arena"\s*\)/)
    end

    it "admits the complete call shape before fast-return paths" do
      source = File.read(File.expand_path("../../src/compiler/hir/ast_to_hir.cr", __DIR__))
      lower_call = source.match(/private\s+def\s+lower_call\b([\s\S]*?)(?=\n\s*private\s+def\s+)/)
      lower_call.should_not be_nil
      admission = lower_call.not_nil![1].match(/call_arena\s*:\s*Adamas::Compiler::Frontend::ArenaLike\s*=\s*@arena([\s\S]*?)trace_lower_call_arena_phase\(ctx, node, "before\.type_like_call"/)
      admission.should_not be_nil
      body = admission.not_nil![1]
      body.should match(/call_args\s*=\s*node\.args/)
      body.should match(/block_expr\s*=\s*node\.block/)
      body.should match(/node_for_call_expr\(\s*call_arena\s*,\s*block_expr\s*\)/)
      body.should match(/call block expression is not owned by call arena/)
      body.should match(/node_for_call_expr\(\s*call_arena\s*,\s*operand\s*\)/)
      body.should match(/call block-pass operand is not owned by call arena/)
      body.should match(/block_expr_index\s*=/)
      body.should match(/has_block_call\s*=/)
    end

    it "routes the whole lower_call block-pass branches through call_arena" do
      source = File.read(File.expand_path("../../src/compiler/hir/ast_to_hir.cr", __DIR__))
      lower_call = source.match(/private\s+def\s+lower_call\b([\s\S]*?)(?=\n\s*private\s+def\s+)/)
      lower_call.should_not be_nil
      lower_call_body = lower_call.not_nil![1]

      inline_branch = lower_call_body.match(/elsif\s+block_pass_expr([\s\S]*?)\n\s*end\s*\n\s*if\s+block_param_types_inline\.nil\?/)
      inline_branch.should_not be_nil
      inline_branch.not_nil![1].should match(/build_block_from_block_pass\(\s*call_arena\s*,/)

      block_id_branch = lower_call_body.match(/block_id\s*=\s*if\s+block_expr([\s\S]*?)\n\s*else\s*\n\s*nil\s*\n\s*end/)
      block_id_branch.should_not be_nil
      block_id_branch.not_nil![1].should match(/elsif\s+block_pass_expr/)
      block_id_branch.not_nil![1].should match(/lower_block_pass_proc\(\s*ctx\s*,\s*call_arena\s*,/)
    end

    it "requires owner-scoped block-pass helper definitions" do
      source = File.read(File.expand_path("../../src/compiler/hir/ast_to_hir.cr", __DIR__))

      build_decl = source.match(/private\s+def\s+build_block_from_block_pass\s*\(([\s\S]*?)\)\s*:\s*Adamas::Compiler::Frontend::BlockNode/)
      build_decl.should_not be_nil
      build_decl.not_nil![1].should match(/\w+_arena\s*:\s*Adamas::Compiler::Frontend::ArenaLike/)
      build_helper = source.match(/private\s+def\s+build_block_from_block_pass\b([\s\S]*?)(?=\n\s*private\s+def\s+)/)
      build_helper.should_not be_nil
      build_body = build_helper.not_nil![1]
      build_body.should_not match(/@arena\s*\[\s*proc_expr\s*\]/)
      build_body.should match(/(?:node_for_call_expr\(\s*\w+_arena\s*,\s*proc_expr|\w+_arena\s*\[\s*proc_expr\s*\]\?|with_arena\(\s*\w+_arena\s*\))/)

      lower_decl = source.match(/private\s+def\s+lower_block_pass_proc\s*\(([\s\S]*?)\)\s*:\s*BlockId/)
      lower_decl.should_not be_nil
      lower_decl.not_nil![1].should match(/\w+_arena\s*:\s*Adamas::Compiler::Frontend::ArenaLike/)
      lower_helper = source.match(/private\s+def\s+lower_block_pass_proc\b([\s\S]*?)(?=\n\s*private\s+def\s+)/)
      lower_helper.should_not be_nil
      lower_body = lower_helper.not_nil![1]
      lower_body.should_not match(/@arena\s*\[\s*proc_expr\s*\]/)
      lower_body.should match(/(?:node_for_call_expr\(\s*\w+_arena\s*,\s*proc_expr|\w+_arena\s*\[\s*proc_expr\s*\]\?|with_arena\(\s*\w+_arena\s*\))/)
    end
  end
end
