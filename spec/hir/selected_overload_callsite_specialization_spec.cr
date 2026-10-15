require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_selected_overload_callsite(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.arena = arena
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  main = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      modules << node
    when Adamas::Compiler::Frontend::CallNode
      main << id.index.to_u64
    end
  end
  modules.each { |node| converter.register_module(node) }
  modules.each { |node| converter.lower_module(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "Selected overload callsite specialization" do
  it "uses the selected abstract numeric restriction after a zero-argument sibling" do
    converter = lower_selected_overload_callsite(<<-CRYSTAL)
      module SelectedOverloadWidth
        extend self

        def extract
          0_i32
        end

        def extract(value : Int)
          value
        end
      end
      SelectedOverloadWidth.extract(0x1_0000_002a_u64)
    CRYSTAL

    function = converter.module.function_by_name("SelectedOverloadWidth.extract$UInt64")
    function.should_not be_nil
    function.not_nil!.params.size.should eq(1)
    function.not_nil!.params.first.type.should eq(Adamas::HIR::TypeRef::UINT64)
    function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::UINT64)
  end

  it "keeps a selected concrete restriction when the base sibling is abstract" do
    converter = lower_selected_overload_callsite(<<-CRYSTAL)
      module SelectedOverloadConcrete
        extend self

        def extract(value : Int, extra : Int32)
          0_u64
        end

        def extract(value : Int32)
          value
        end
      end
      SelectedOverloadConcrete.extract(42)
    CRYSTAL

    function = converter.module.function_by_name("SelectedOverloadConcrete.extract$Int32")
    function.should_not be_nil
    function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "preserves the selected definition through an extended module" do
    converter = lower_selected_overload_callsite(<<-CRYSTAL)
      module SelectedOverloadProducer
        def extract
          0_i32
        end

        def extract(value : Int)
          value
        end
      end
      module SelectedOverloadConsumer
        extend SelectedOverloadProducer
      end
      SelectedOverloadConsumer.extract(0x1_0000_002a_u64)
    CRYSTAL

    function = converter.module.function_by_name("SelectedOverloadConsumer.extract$UInt64")
    function.should_not be_nil
    function.not_nil!.params.size.should eq(1)
    function.not_nil!.params.first.type.should eq(Adamas::HIR::TypeRef::UINT64)
    function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::UINT64)
  end
end
