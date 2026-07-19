require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/owned_expr_ref"
require "../../src/compiler/hir/ast_to_hir"

private def parse_roots(source : String, arena : Adamas::Compiler::Frontend::AstArena? = nil)
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = if arena
             Adamas::Compiler::Frontend::Parser.new(lexer, arena)
           else
             Adamas::Compiler::Frontend::Parser.new(lexer)
           end
  {parser, parser.parse_program_roots}
end

private def retained_identifier_ref : Adamas::Compiler::Frontend::OwnedExprRef
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new("retained_name\n"),
  )
  root = parser.parse_program_roots.first
  Adamas::Compiler::Frontend::OwnedExprRef.parsed(
    parser.arena,
    root,
  )
end

describe Adamas::Compiler::Frontend::OwnedExprRef do
  it "keeps equal local ids from independent owners distinct" do
    source = "value = 1\n"
    first_parser, first_roots = parse_roots(source)
    second_parser, second_roots = parse_roots(source)

    first_id = first_roots.first
    second_id = second_roots.first
    first_id.should eq second_id
    first_parser.arena[first_id].span.should eq second_parser.arena[second_id].span
    first_parser.arena.debug_node_address(first_id).should_not eq second_parser.arena.debug_node_address(second_id)

    first_ref = Adamas::Compiler::Frontend::OwnedExprRef.parsed(
      first_parser.arena,
      first_id,
    )
    second_ref = Adamas::Compiler::Frontend::OwnedExprRef.parsed(
      second_parser.arena,
      second_id,
    )

    first_ref.arena.should_not be second_ref.arena
    first_ref.expr_id.should eq second_ref.expr_id
    first_ref.arena.debug_node_address(first_ref.expr_id).should_not eq second_ref.arena.debug_node_address(second_ref.expr_id)
  end

  it "fails closed for foreign canonical-view ids" do
    shared = Adamas::Compiler::Frontend::AstArena.new
    first_parser, first_roots = parse_roots("class First\nend\n", shared)
    second_start = shared.size
    _second_parser, second_roots = parse_roots("class Second\nend\n", shared)
    second_end = shared.size

    first_view = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(shared, 0, second_start, "class First\nend\n", second_end)
    second_view = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(shared, second_start, second_end, "class Second\nend\n", second_end)
    first_id = first_roots.first
    second_id = second_roots.first

    first_ref = Adamas::Compiler::Frontend::OwnedExprRef.parsed(
      first_view,
      first_id,
    )
    first_ref.fetch.should eq shared[first_id]

    generated_ref = Adamas::Compiler::Frontend::OwnedExprRef.capture_macro_expansion(first_view) do |owner|
      owner.as(Adamas::Compiler::Frontend::CanonicalSyntaxView).add(shared[first_id])
    end.not_nil!
    generated_ref.fetch.should eq shared[generated_ref.expr_id]

    expect_raises(ArgumentError) do
      Adamas::Compiler::Frontend::OwnedExprRef.parsed(
        first_view,
        second_id,
      )
    end
    foreign_generated = second_view.add(shared[second_id])
    expect_raises(ArgumentError) do
      Adamas::Compiler::Frontend::OwnedExprRef.capture_macro_expansion(first_view) do |_owner|
        foreign_generated
      end
    end
    expect_raises(ArgumentError) do
      Adamas::Compiler::Frontend::OwnedExprRef.capture_macro_expansion(first_view) do |_owner|
        generated_ref.expr_id
      end
    end
  end

  it "rejects invalid ids and non-AstArena owners" do
    arena = Adamas::Compiler::Frontend::AstArena.new
    id = arena.add(Adamas::Compiler::Frontend::NilNode.new(Adamas::Compiler::Frontend::Span.zero))

    expect_raises(ArgumentError) do
      Adamas::Compiler::Frontend::OwnedExprRef.parsed(
        arena,
        Adamas::Compiler::Frontend::ExprId.new(-1),
      )
    end
    Adamas::Compiler::Frontend::OwnedExprRef.capture_macro_expansion(arena) do |_owner|
      Adamas::Compiler::Frontend::ExprId.new(-1)
    end.should be_nil
    expect_raises(ArgumentError) do
      Adamas::Compiler::Frontend::OwnedExprRef.capture_macro_expansion(arena) do |_owner|
        id
      end
    end
    expect_raises(ArgumentError) do
      Adamas::Compiler::Frontend::OwnedExprRef.capture_macro_expansion(arena) do |_owner|
        Adamas::Compiler::Frontend::ExprId.new(99)
      end
    end

    virtual = Adamas::Compiler::Frontend::VirtualArena.new
    page = Adamas::Compiler::Frontend::PageArena.new
    expect_raises(ArgumentError) do
      Adamas::Compiler::Frontend::OwnedExprRef.parsed(
        virtual,
        id,
      )
    end
    expect_raises(ArgumentError) do
      Adamas::Compiler::Frontend::OwnedExprRef.capture_macro_expansion(page) do |_owner|
        id
      end
    end
  end

  it "retains the owner and interned slices after parser locals disappear" do
    ref = retained_identifier_ref

    8.times do |round|
      churn = Array(String).new(256) { |index| "owned-ref-churn-#{round}-#{index}" }
      churn.size.should eq 256
      GC.collect
    end

    node = ref.fetch.as(Adamas::Compiler::Frontend::IdentifierNode)
    String.new(node.name).should eq "retained_name"
  end

  it "preserves the four-byte ExprId ABI" do
    sizeof(Adamas::Compiler::Frontend::ExprId).should eq 4
  end

  it "requires lower_expanded_macro_result to consume an owner-tagged ref" do
    source = File.read(File.join(__DIR__, "../../src/compiler/hir/ast_to_hir.cr"))
    start = source.index("private def lower_expanded_macro_result").not_nil!
    finish = source.index("private def expand_macro(", start).not_nil!
    body = source[start...finish]
    source.should contain("OwnedExprRef.capture_macro_expansion")
    source.scan(/do \|owned_arena\|/).size.should eq 2
    source.scan(/expand_macro_expr\(macro_def, owned_arena/).size.should eq 2
    source.should contain("lower_expanded_macro_result(ctx, expanded_ref)")
    body.should contain("expanded_ref.fetch?")
    body.should contain("@arena = expanded_ref.arena")
    body.should_not contain("arena_for_expr?")
    body.should_not contain(".size")
    body.should_not contain("span")
    source.should_not contain("lower_expanded_macro_result(ctx, macro_arena, expanded_id)")
    source.should_not contain("OwnedExprRef.try_macro_expansion")
    source.should_not contain("pre_expansion_size")
  end
end
