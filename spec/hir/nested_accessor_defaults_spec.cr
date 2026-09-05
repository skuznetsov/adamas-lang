require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

describe "Nested typed accessor defaults" do
  {"class", "struct"}.each do |kind|
    it "retains the expansion arena for a #{kind} default" do
      macro_source = "macro add_default\n property level : Int32 = 42\nend"
      macro_result = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(macro_source),
      ).parse_program
      macro_arena = macro_result.arena
      source = <<-SOURCE
        #{kind} DefaultOwner
          add_default()
        end
      SOURCE
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(source),
      )
      result = parser.parse_program
      arena = result.arena
      converter = Adamas::HIR::AstToHir.new(
        arena, sources_by_arena: {
          arena.object_id.to_u64 => source,
          macro_arena.object_id.to_u64 => macro_source,
        },
      )
      macro_node = macro_result.roots.compact_map do |id|
        macro_arena[id].as?(Adamas::Compiler::Frontend::MacroDefNode)
      end.first
      owner = result.roots.compact_map do |id|
        arena[id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first
      converter.arena = macro_arena
      converter.register_macro(macro_node)
      converter.arena = arena
      converter.register_class(owner)
      converter.lower_class(owner)
      ivar = converter.class_info["DefaultOwner"].ivars.find(&.name.==("@level")).not_nil!
      ivar.type.should eq(Adamas::HIR::TypeRef::INT32)
      default_arena = ivar.default_arena.not_nil!
      default_arena.object_id.should_not eq(arena.object_id)
      literal = default_arena[ivar.default_expr_id.not_nil!].as(Adamas::Compiler::Frontend::NumberNode)
      String.new(literal.value).should eq("42")
      converter.module.function_by_name("DefaultOwner#level").should_not be_nil
      converter.module.function_by_name("DefaultOwner#level=$Int32").should_not be_nil
    end
  end
end
