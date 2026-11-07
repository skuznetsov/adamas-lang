require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def spec_arity_type_ref(name : String) : TypeRef
    type_ref_for_name(name)
  end

  def spec_has_source_overload?(name : String, arg_types : Array(TypeRef)) : Bool
    !lookup_function_def_for_call(name, arg_types.size, false, arg_types).nil?
  end
end

describe "required-argument-only member source overload" do
  it "does not present a required-argument method as an arity-zero target" do
    source = <<-CRYSTAL
      class ReplayRequiredOnly
        def to_slice(flag : Bool) : Int32
          flag ? 2 : 3
        end
      end
      CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    program.roots.each do |root|
      case node = arena[root]
      when Adamas::Compiler::Frontend::ClassNode
        converter.register_class(node)
      end
    end

    converter.spec_has_source_overload?("ReplayRequiredOnly#to_slice", [] of Adamas::HIR::TypeRef).should be_false
    converter.spec_has_source_overload?(
      "ReplayRequiredOnly#to_slice",
      [converter.spec_arity_type_ref("Bool")],
    ).should be_true
  end
end
