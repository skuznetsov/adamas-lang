require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_ivar_type_name_for_subtype_union(owner : String, name : String) : String
    info = @class_info[owner]
    ivar = info.ivars.find { |candidate| candidate.name == name } || raise "missing #{owner}#{name}"
    get_type_name_from_ref(ivar.type)
  end

  def __test_type_ref_for_subtype_union(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __test_type_name_for_subtype_union(type_ref : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type_ref)
  end

  def __test_merge_subtype_union(
    left : Adamas::HIR::TypeRef,
    right : Adamas::HIR::TypeRef,
  ) : Adamas::HIR::TypeRef
    union_type_for_values(left, right)
  end
end

private def lower_subtype_union_program(code : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(code))
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  defs = [] of Adamas::Compiler::Frontend::DefNode
  result.roots.each do |expr_id|
    node = result.arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::DefNode
      defs << node
    end
  end

  classes.each { |node| converter.register_class(node) }
  defs.each { |node| converter.register_function(node) }
  classes.each { |node| converter.lower_class(node) }
  defs.each { |node| converter.lower_def(node) }
  converter
end

describe "redundant subtype unions" do
  it "keeps an explicitly typed base-class ivar canonical after a subclass default" do
    converter = lower_subtype_union_program(<<-CRYSTAL)
      abstract class TermBase
      end

      class ReturnTerm < TermBase
      end

      class JumpTerm < TermBase
      end

      class TermBaseExtra
      end

      class TermBlock
        getter terminator : TermBase

        def initialize
          @terminator = JumpTerm.new
        end
      end

      def return_term?(block : TermBlock) : Bool
        case block.terminator
        when ReturnTerm
          true
        else
          false
        end
      end
    CRYSTAL

    converter.__test_ivar_type_name_for_subtype_union("TermBlock", "@terminator").should eq("TermBase")

    function = converter.module.functions.find { |candidate| candidate.name.starts_with?("return_term?$") }
    function.should_not be_nil
    text = String.build { |io| function.not_nil!.to_s(io) }
    text.should contain("is_a")
    text.should_not contain("Union TermBase | JumpTerm")

    parent = converter.__test_type_ref_for_subtype_union("TermBase")
    return_term = converter.__test_type_ref_for_subtype_union("ReturnTerm")
    jump_term = converter.__test_type_ref_for_subtype_union("JumpTerm")
    unrelated = converter.__test_type_ref_for_subtype_union("TermBaseExtra")
    nilable_parent = converter.__test_type_ref_for_subtype_union("TermBase?")

    converter.__test_merge_subtype_union(parent, return_term).should eq(parent)
    converter.__test_merge_subtype_union(return_term, parent).should eq(parent)
    converter.__test_merge_subtype_union(nilable_parent, return_term).should eq(nilable_parent)

    sibling_union = converter.__test_merge_subtype_union(return_term, jump_term)
    sibling_name = converter.__test_type_name_for_subtype_union(sibling_union)
    sibling_name.should contain("ReturnTerm")
    sibling_name.should contain("JumpTerm")

    unrelated_union = converter.__test_merge_subtype_union(parent, unrelated)
    unrelated_name = converter.__test_type_name_for_subtype_union(unrelated_union)
    unrelated_name.should contain("TermBase")
    unrelated_name.should contain("TermBaseExtra")
  end
end
