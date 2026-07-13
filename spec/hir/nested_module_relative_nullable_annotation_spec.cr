require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_type_name_for_nested_nullable(type_ref : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type_ref)
  end

  def __test_resolve_nested_nullable_annotation(name : String, owner : String) : Adamas::HIR::TypeRef
    annotation_type_ref(name, owner)
  end
end

private def lower_nested_nullable_program(code : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(code))
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena

  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  defs = [] of Adamas::Compiler::Frontend::DefNode
  main_exprs = [] of UInt64

  result.roots.each do |expr_id|
    node = result.arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      modules << node
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::DefNode
      defs << node
    when Adamas::Compiler::Frontend::CallNode
      main_exprs << expr_id.index.to_u64
    end
  end

  # mir.cr requires layout_contract.cr before MIR::Type exists. Model that
  # registration order by forcing the annotation cache before nested types are
  # registered.
  converter.__test_resolve_nested_nullable_annotation("MIR::Type?", "Outer::Check")

  modules.each { |node| converter.register_module(node) }
  classes.each { |node| converter.register_class(node) }
  defs.each { |node| converter.register_function(node) }
  modules.each { |node| converter.lower_module(node) }
  classes.each { |node| converter.lower_class(node) }
  defs.each { |node| converter.lower_def(node) }
  converter.lower_main(main_exprs)
  converter
end

private def nested_nullable_hir_text(function : Adamas::HIR::Function) : String
  String.build { |io| function.to_s(io) }
end

describe "nested-module relative nullable annotations" do
  it "keeps the enclosing namespace through the nullable member and enum predicate chain" do
    converter = lower_nested_nullable_program(<<-CRYSTAL)
      class MIR::Type
        def kind : Int32
          0
        end
      end

      module Outer
        enum ItemKind
          Tuple
          Other
        end

        module Check
          def self.tuple?(type : MIR::Type?) : Bool
            return false unless type
            type.kind.tuple?
          end
        end

        module MIR
          class Type
            def kind : ItemKind
              ItemKind::Tuple
            end
          end
        end
      end

      def probe(value : Outer::MIR::Type) : Bool
        Outer::Check.tuple?(value)
      end

      probe(uninitialized Outer::MIR::Type)
    CRYSTAL

    function = converter.module.functions.find do |candidate|
      candidate.name.starts_with?("Outer::Check.tuple?$")
    end
    function.should_not be_nil

    param_type = function.not_nil!.params.first.type
    param_name = converter.__test_type_name_for_nested_nullable(param_type)
    param_name.should eq("Nil | Outer::MIR::Type")

    explicit_top_level = converter.__test_resolve_nested_nullable_annotation("::String?", "Outer::Check")
    converter.__test_type_name_for_nested_nullable(explicit_top_level).should eq("Nil | String")

    canonical = converter.__test_resolve_nested_nullable_annotation("Outer::MIR::Type?", "Outer::Check")
    converter.__test_type_name_for_nested_nullable(canonical).should eq("Nil | Outer::MIR::Type")

    non_nullable = converter.__test_resolve_nested_nullable_annotation("MIR::Type", "Outer::Check")
    converter.__test_type_name_for_nested_nullable(non_nullable).should eq("Outer::MIR::Type")

    text = nested_nullable_hir_text(function.not_nil!)
    text.should contain("Outer::MIR::Type#kind")
    text.should_not contain(".tuple?()")
  end
end
