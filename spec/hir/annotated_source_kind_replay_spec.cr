require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def spec_force_annotated_kind_consumer(name : String) : Bool
    remember_callsite_arg_types(name, [] of TypeRef)
    saved_depth = @force_lower_return_type_depth
    @force_lower_return_type_depth = 3
    begin
      force_lower_function_for_return_type(name)
    ensure
      @force_lower_return_type_depth = saved_depth
    end
  end
end

describe "annotated exact source result replay" do
  it "settles source kind before narrowing a nullable call with a known ABI" do
    source = <<-CRYSTAL
      class AnnotatedKindOwner
        def self.maybe(flag : Bool) : String?
          if flag
            "prefix"
          else
            nil
          end
        end
        def self.accept(value : String) : Int32
          65
        end
        def self.consume : Int32
          if prefix = maybe(true)
            accept(prefix)
          else
            66
          end
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
    converter.spec_force_annotated_kind_consumer("AnnotatedKindOwner.consume").should be_true
    converter.flush_pending_functions
    function = converter.module.function_by_name("AnnotatedKindOwner.consume").not_nil!
    function.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    function.blocks.any?(&.body_emitted).should be_true
  end
end
