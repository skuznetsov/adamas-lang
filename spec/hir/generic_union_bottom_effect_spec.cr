require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_generic_union_bottom_effect(owner : String, block_call = false, splat = false) : Bool
    concrete_class_virtual_targets_noreturn?(owner, "stop", [] of TypeRef, block_call, splat)
  end
end

private def generic_union_effect_fixture(source : String) : Adamas::HIR::AstToHir
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)).parse_program
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  parsed.roots.each do |id|
    case node = parsed.arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      converter.lower_class(node)
    end
  end
  converter
end

describe "generic union bottom effect certificate" do
  it "accepts an explicit bottom class target" do
    converter = generic_union_effect_fixture("class BottomBase\ndef stop : NoReturn\nraise \"stop\"\nend\nend")
    converter.__test_generic_union_bottom_effect("BottomBase").should be_true
  end

  it "rejects a returning override even when the parent is explicitly bottom" do
    converter = generic_union_effect_fixture(<<-CRYSTAL)
      class BottomBase
        def stop : NoReturn
          raise "stop"
        end
      end
      class ReturningChild < BottomBase
        def stop
          "returned"
        end
      end
    CRYSTAL
    converter.__test_generic_union_bottom_effect("BottomBase").should be_false
  end

  it "accepts a descendant only when its own selected target is bottom" do
    converter = generic_union_effect_fixture(<<-CRYSTAL)
      class BottomBase
        def stop : NoReturn
          raise "base"
        end
      end
      class BottomChild < BottomBase
        def stop : NoReturn
          raise "child"
        end
      end
    CRYSTAL
    converter.__test_generic_union_bottom_effect("BottomBase").should be_true
  end

  it "does not infer a certificate from an unmaterialized raising body" do
    converter = generic_union_effect_fixture("class UnknownEffect\ndef stop\nraise \"stop\"\nend\nend")
    converter.__test_generic_union_bottom_effect("UnknownEffect").should be_false
  end

  it "keeps block and splat calls outside the certificate" do
    converter = generic_union_effect_fixture("class BottomBase\ndef stop : NoReturn\nraise \"stop\"\nend\nend")
    converter.__test_generic_union_bottom_effect("BottomBase", block_call: true).should be_false
    converter.__test_generic_union_bottom_effect("BottomBase", splat: true).should be_false
  end
end
