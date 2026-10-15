require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_materialize_generic_placeholder(name : String, params : Array(Adamas::HIR::TypeRef))
    before = @module.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Generic, name, params))
    # Mirror the placeholder retained by an earlier annotation lookup.
    store_type_cache(type_cache_key(name), before)
    ensure_monomorphized_type(before)
    {before, @class_info[name]?.try(&.type_ref), @module.get_type_descriptor(before)}
  end
end

private def nested_placeholder_converter(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena, sources_by_arena: {program.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |root|
    if node = program.arena[root].as?(Adamas::Compiler::Frontend::ModuleNode)
      converter.register_module(node)
    end
  end
  converter
end

describe "concrete declaration after a nested generic placeholder" do
  it "preserves class identity and parameters while enabling concrete dispatch" do
    converter = nested_placeholder_converter(<<-CRYSTAL)
      module PlaceholderScope(T)
        class Nested(U)
          def initialize(@value : U); end
          def value : U; @value; end
        end
      end
    CRYSTAL
    name = "PlaceholderScope(T)::Nested(Int32)"
    before, after, descriptor = converter.__test_materialize_generic_placeholder(name, [Adamas::HIR::TypeRef::INT32])
    after.should eq(before)
    descriptor.not_nil!.name.should eq(name)
    descriptor.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Class)
    descriptor.not_nil!.type_params.should eq([Adamas::HIR::TypeRef::INT32])
  end

  it "preserves the declared value kind for a nested generic struct" do
    converter = nested_placeholder_converter(<<-CRYSTAL)
      module PlaceholderScope(T)
        struct Nested(U)
          def initialize(@value : U); end
        end
      end
    CRYSTAL
    name = "PlaceholderScope(T)::Nested(Int64)"
    before, after, descriptor = converter.__test_materialize_generic_placeholder(name, [Adamas::HIR::TypeRef::INT64])
    after.should eq(before)
    descriptor.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Struct)
    descriptor.not_nil!.type_params.should eq([Adamas::HIR::TypeRef::INT64])
  end

  it "keeps an unknown nested owner unresolved" do
    converter = nested_placeholder_converter(<<-CRYSTAL)
      module PlaceholderScope(T)
        class Nested(U)
        end
      end
    CRYSTAL
    before, after, descriptor = converter.__test_materialize_generic_placeholder(
      "OtherScope(T)::Missing(Int32)", [Adamas::HIR::TypeRef::INT32])
    after.should be_nil
    descriptor.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Generic)
  end
end
