require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_enum_self_return_type(name : String) : Adamas::HIR::TypeRef?
    @function_types[name]?
  end

  def __test_enum_self_base_return_type(name : String) : Adamas::HIR::TypeRef?
    @function_base_return_types[name]?
  end

  def __test_enum_self_named_type(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __test_enum_self_return_source?(name : String, source_name : String) : Bool
    target = @function_defs[name]?
    source = @function_defs[source_name]?
    !!(target && source && target.same?(source))
  end
end

private def enum_self_return_fixture(enum_first : Bool) : Adamas::HIR::AstToHir
  parent = <<-CRYSTAL
    abstract struct Enum
      def self.semantic_self_return : self
        self.new(1)
      end

      def semantic_instance_self_return : self
        self
      end

      def self.explicit_root_return : Enum
        self.new(1)
      end

      def self.explicit_numeric_return : Int64
        1_i64
      end
    end
    CRYSTAL
  enums = <<-CRYSTAL
    enum NarrowSelfReturnKind : UInt8
      One = 1
    end

    enum WideSelfReturnKind : UInt64
      One = 1
    end

    enum UserSelfReturnKind
      One = 1

      def self.semantic_self_return : String
        "user"
      end
    end

    struct UnrelatedSelfReturnKind
      def self.semantic_self_return : self
        new
      end
    end
    CRYSTAL
  source = enum_first ? "#{enums}\n#{parent}" : "#{parent}\n#{enums}"
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.arena = arena
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::EnumNode
      converter.register_enum(node)
    end
  end
  converter
end

describe "inherited Enum :self return specialization" do
  [false, true].each do |enum_first|
    context(enum_first ? "batch attachment after enum registration" : "attachment during enum registration") do
      it "uses each concrete enum's carrier before lowering a class method" do
        converter = enum_self_return_fixture(enum_first)
        {"NarrowSelfReturnKind" => Adamas::HIR::TypeRef::UINT8,
         "WideSelfReturnKind" => Adamas::HIR::TypeRef::UINT64}.each do |owner, expected|
          name = "#{owner}.semantic_self_return"
          converter.__test_enum_self_return_source?(name, "Enum.semantic_self_return").should be_true
          converter.__test_enum_self_return_type(name).should eq(expected)
          converter.__test_enum_self_base_return_type(name).should eq(expected)
        end
      end

      it "also projects attached instance :self returns" do
        converter = enum_self_return_fixture(enum_first)
        converter.__test_enum_self_return_type("WideSelfReturnKind#semantic_instance_self_return")
          .should eq(Adamas::HIR::TypeRef::UINT64)
      end

      it "preserves explicit Enum and numeric contracts" do
        converter = enum_self_return_fixture(enum_first)
        converter.__test_enum_self_return_type("WideSelfReturnKind.explicit_root_return")
          .should eq(converter.__test_enum_self_named_type("Enum"))
        converter.__test_enum_self_return_type("WideSelfReturnKind.explicit_numeric_return")
          .should eq(Adamas::HIR::TypeRef::INT64)
      end

      it "preserves user overrides and unrelated owners" do
        converter = enum_self_return_fixture(enum_first)
        converter.__test_enum_self_return_source?("UserSelfReturnKind.semantic_self_return", "Enum.semantic_self_return")
          .should be_false
        converter.__test_enum_self_return_type("UserSelfReturnKind.semantic_self_return")
          .should eq(converter.__test_enum_self_named_type("String"))
        converter.__test_enum_self_return_type("UnrelatedSelfReturnKind.semantic_self_return")
          .should eq(converter.__test_enum_self_named_type("UnrelatedSelfReturnKind"))
      end
    end
  end
end
