require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def register_macro_ivar_declaration_fixture(declaration : String)
  source = <<-CRYSTAL
    struct StackValue
      def initialize(@a : Int64, @b : Int64, @c : Int64)
      end
    end
    class StackOwner
      #{declaration}
      def put(value : StackValue)
        @stack = value
      end
      def read : StackValue?
        @stack
      end
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source})
  program.roots.each do |id|
    node = arena[id]
    converter.register_class(node) if node.is_a?(Adamas::Compiler::Frontend::ClassNode)
  end
  converter
end

describe "macro class ivar declaration registration" do
  {
    "direct declaration" => "@stack : StackValue?",
    "selected if" => "{% if true %}\n@stack : StackValue?\n{% end %}",
    "selected else" => "{% if false %}\n@unused : Bool\n{% else %}\n@stack : StackValue?\n{% end %}",
    "selected elsif" => "{% if false %}\n@unused : Bool\n{% elsif true %}\n@stack : StackValue?\n{% end %}",
    "nested if" => "{% if true %}\n{% if true %}\n@stack : StackValue?\n{% end %}\n{% end %}",
    "begin expansion" => "{% begin %}\n@stack : StackValue?\n{% end %}",
    "threaded branch" => "{% if true %}\n{% name = \"stack\" %}\n@{{name.id}} : StackValue?\n{% end %}",
  }.each do |label, declaration|
    it "preserves the nullable value type from a #{label}" do
      converter = register_macro_ivar_declaration_fixture(declaration)
      owner = converter.class_info["StackOwner"]
      fields = owner.ivars.select { |ivar| ivar.name == "@stack" }
      fields.size.should eq(1)
      descriptor = converter.module.get_type_descriptor(fields.first.type).not_nil!
      descriptor.kind.should eq(Adamas::HIR::TypeKind::Union)
      descriptor.name.should eq("Nil | StackValue")
      owner.ivars.any? { |ivar| ivar.name == "@unused" }.should be_false
    end
  end
end
