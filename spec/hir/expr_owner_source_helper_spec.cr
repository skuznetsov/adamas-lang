require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_stringify_type_expr_owned(
    owner : Adamas::Compiler::Frontend::ArenaLike,
    expr_id : Adamas::Compiler::Frontend::ExprId,
  ) : String?
    stringify_type_expr_owned(expr_id, owner)
  end

  def __test_infer_type_literal_name_owned(
    owner : Adamas::Compiler::Frontend::ArenaLike,
    expr_id : Adamas::Compiler::Frontend::ExprId,
  ) : String?
    infer_type_literal_name_from_expr_owned(expr_id, owner)
  end

  def __test_tail_expr_id_for_body(
    owner : Adamas::Compiler::Frontend::ArenaLike,
    body : Array(Adamas::Compiler::Frontend::ExprId),
  ) : Adamas::Compiler::Frontend::ExprId?
    tail_expr_id_for_body(body, owner)
  end
end

private SPAN = Adamas::Compiler::Frontend::Span.new(0, 0, 1, 1, 1, 1)

private def identifier(arena : Adamas::Compiler::Frontend::AstArena, name : String)
  arena.add_typed(Adamas::Compiler::Frontend::IdentifierNode.new(SPAN, name.to_slice))
end

describe Adamas::HIR::AstToHir do
  describe "owner-threaded source helpers" do
    it "routes equal plain ExprIds through the explicitly supplied owner" do
      first = Adamas::Compiler::Frontend::AstArena.new
      second = Adamas::Compiler::Frontend::AstArena.new
      first_id = identifier(first, "FirstType")
      second_id = identifier(second, "SecondType")
      first_id.should eq second_id

      converter = Adamas::HIR::AstToHir.new(first)
      converter.__test_stringify_type_expr_owned(second, second_id).should eq "SecondType"
      converter.__test_stringify_type_expr_owned(first, first_id).should eq "FirstType"
    end

    it "fails closed for foreign canonical generated and out-of-range ids" do
      source_owner = Adamas::Compiler::Frontend::AstArena.new
      parsed_id = source_owner.add_typed(Adamas::Compiler::Frontend::IdentifierNode.new(SPAN, "ParsedFirst".to_slice))
      foreign_parsed_id = source_owner.add_typed(Adamas::Compiler::Frontend::IdentifierNode.new(SPAN, "ParsedSecond".to_slice))
      first = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(source_owner, 0, 1, parsed_limit: 2)
      second = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(source_owner, 1, 2, parsed_limit: 2)
      foreign_id = second.add(Adamas::Compiler::Frontend::IdentifierNode.new(SPAN, "Foreign".to_slice))
      foreign_child_path = first.add(Adamas::Compiler::Frontend::PathNode.new(SPAN, foreign_id, foreign_id))
      converter = Adamas::HIR::AstToHir.new(first)

      converter.__test_stringify_type_expr_owned(first, parsed_id).should eq "ParsedFirst"
      converter.__test_stringify_type_expr_owned(first, foreign_id).should be_nil
      converter.__test_stringify_type_expr_owned(first, foreign_parsed_id).should be_nil
      converter.__test_stringify_type_expr_owned(first, Adamas::Compiler::Frontend::ExprId.new(99)).should be_nil
      converter.__test_stringify_type_expr_owned(first, foreign_child_path).should be_nil
      converter.__test_infer_type_literal_name_owned(first, foreign_id).should be_nil
    end

    it "keeps recursive generic children on the retained owner" do
      first = Adamas::Compiler::Frontend::AstArena.new
      second = Adamas::Compiler::Frontend::AstArena.new
      first_base = identifier(first, "FirstBase")
      second_base = identifier(second, "SecondBase")
      first_arg = identifier(first, "FirstArg")
      second_arg = identifier(second, "SecondArg")
      first_generic = first.add_typed(Adamas::Compiler::Frontend::GenericNode.new(SPAN, first_base, [first_arg]))
      second_generic = second.add_typed(Adamas::Compiler::Frontend::GenericNode.new(SPAN, second_base, [second_arg]))

      converter = Adamas::HIR::AstToHir.new(first)
      converter.__test_stringify_type_expr_owned(second, second_generic).should eq "SecondBase(SecondArg)"
      converter.__test_stringify_type_expr_owned(first, first_generic).should eq "FirstBase(FirstArg)"
    end

    it "fails closed when a retained-owner wrapper points to a foreign child" do
      source_owner = Adamas::Compiler::Frontend::AstArena.new
      parsed_first = source_owner.add_typed(Adamas::Compiler::Frontend::IdentifierNode.new(SPAN, "First".to_slice))
      parsed_second = source_owner.add_typed(Adamas::Compiler::Frontend::IdentifierNode.new(SPAN, "Second".to_slice))
      first = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(source_owner, 0, 1, parsed_limit: 2)
      converter = Adamas::HIR::AstToHir.new(first)
      local_wrapper = first.add(Adamas::Compiler::Frontend::GroupingNode.new(SPAN, parsed_first))
      foreign_wrapper = first.add(Adamas::Compiler::Frontend::GroupingNode.new(SPAN, parsed_second))

      converter.__test_tail_expr_id_for_body(first, [local_wrapper]).should eq parsed_first
      converter.__test_tail_expr_id_for_body(first, [foreign_wrapper]).should be_nil
    end

    it "uses the retained owner for path source text" do
      first = Adamas::Compiler::Frontend::AstArena.new
      second = Adamas::Compiler::Frontend::AstArena.new
      first_left = identifier(first, "First")
      first_right = identifier(first, "Type")
      first_path = first.add_typed(Adamas::Compiler::Frontend::PathNode.new(SPAN, first_left, first_right))
      second_left = identifier(second, "Second")
      second_right = identifier(second, "Type")
      second_path = second.add_typed(Adamas::Compiler::Frontend::PathNode.new(SPAN, second_left, second_right))

      converter = Adamas::HIR::AstToHir.new(first)
      converter.__test_stringify_type_expr_owned(second, second_path).should eq "Second::Type"
      converter.__test_stringify_type_expr_owned(first, first_path).should eq "First::Type"
    end

    it "keeps the owner-threaded helper free of heuristic owner recovery" do
      source = File.read(File.join(__DIR__, "../../src/compiler/hir/ast_to_hir.cr"))
      stringify_start = source.index("private def stringify_type_expr_owned").not_nil!
      stringify_finish = source.index("private def type_like_expr_id?", stringify_start).not_nil!
      infer_start = source.index("private def infer_type_literal_name_from_expr_owned").not_nil!
      infer_finish = source.index("private def infer_type_literal_return_name_from_body", infer_start).not_nil!
      source[stringify_start...stringify_finish].should_not contain("arena_for_expr?")
      source[infer_start...infer_finish].should_not contain("arena_for_expr?")
      source[stringify_start...stringify_finish].should_not contain("nodes")
      source[infer_start...infer_finish].should_not contain("nodes")
      tail_start = source.index("private def tail_expr_id_for_body(").not_nil!
      tail_finish = source.index("private def infer_type_literal_name_from_expr", tail_start).not_nil!
      source[tail_start...tail_finish].should contain("owner : Adamas::Compiler::Frontend::ArenaLike? = nil")
      source[tail_start...tail_finish].should contain("exact_owner_node_for_expr(retained_owner, expr_id)")
    end
  end
end
