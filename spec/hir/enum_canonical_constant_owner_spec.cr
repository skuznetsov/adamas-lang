require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_canonical_enum_member(owner : String, member : String, namespace : String) : Int64?
    with_namespace_override(namespace) { enum_constant_member_value(owner, member) }
  end
end

private def canonical_enum_owner_fixture : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    module Registry
      enum Kind : UInt8
        BlockDevice = 65
      end
      @[Flags]
      enum Options : UInt8
        Read = 1
        Write = 2
      end
    end
    module Shadow
      module Registry
        enum Kind : UInt8
          Other = 88
        end
        enum Options : UInt8
          Other = 88
        end
      end
      class Reader
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
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end
  converter
end

describe "canonical enum constant owner" do
  it "keeps a resolved enum owner stable across namespace lookup" do
    converter = canonical_enum_owner_fixture
    converter.__test_canonical_enum_member("Registry::Kind", "BlockDevice", "Shadow::Reader").should eq(65_i64)
    converter.__test_canonical_enum_member("Shadow::Registry::Kind", "Other", "Shadow::Reader").should eq(88_i64)
  end

  it "uses the canonical owner for synthesized Flags constants" do
    converter = canonical_enum_owner_fixture
    converter.__test_canonical_enum_member("Registry::Options", "All", "Shadow::Reader").should eq(3_i64)
    converter.__test_canonical_enum_member("Registry::Options", "None", "Shadow::Reader").should eq(0_i64)
    converter.__test_canonical_enum_member("Shadow::Registry::Options", "All", "Shadow::Reader").should be_nil
  end

  it "never borrows a missing member from a shadowing enum or folds its spelling" do
    converter = canonical_enum_owner_fixture
    converter.__test_canonical_enum_member("Registry::Kind", "Other", "Shadow::Reader").should be_nil
    converter.__test_canonical_enum_member("Registry::Kind", "BLOCKDEVICE", "Shadow::Reader").should be_nil
    converter.__test_canonical_enum_member("Registry::Options", "ALL", "Shadow::Reader").should be_nil
  end
end
