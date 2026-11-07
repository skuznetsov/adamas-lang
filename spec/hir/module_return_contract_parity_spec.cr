require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_module_return_types(prefix : String) : Array(String)
    @module.functions.compact_map do |function|
      if function.name.starts_with?(prefix) && @module.has_function_with_body?(function.name)
        get_type_name_from_ref(function.return_type)
      end
    end
  end
end

private def lower_module_return_contract_source(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/module_return_contract_parity_spec.cr"},
  )
  converter.no_prelude = true

  main = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << id.index.to_u64
    end
  end
  {converter, main}
end

describe "module method source return contracts" do
  it "rejects an invalid implicit result before coercion" do
    converter, main = lower_module_return_contract_source(<<-CRYSTAL)
      class ModuleReturnExpected
      end

      class ModuleReturnActual
      end

      module ModuleReturnImplicitOwner
        def self.bad(flag : Bool) : ModuleReturnExpected
          if flag
            ModuleReturnActual.new
          else
            ModuleReturnActual.new
          end
        end
      end

      ModuleReturnImplicitOwner.bad(true)
    CRYSTAL

    expect_raises(Adamas::HIR::LoweringError, /must return ModuleReturnExpected/) do
      converter.lower_main(main)
      converter.flush_pending_functions
    end
  end

  it "routes explicit returns through the same source contract" do
    converter, main = lower_module_return_contract_source(<<-CRYSTAL)
      class ModuleReturnExplicitExpected
      end

      class ModuleReturnExplicitActual
      end

      module ModuleReturnExplicitOwner
        def self.bad(flag : Bool) : ModuleReturnExplicitExpected
          if flag
            return ModuleReturnExplicitActual.new
          end
          ModuleReturnExplicitExpected.new
        end
      end

      ModuleReturnExplicitOwner.bad(true)
    CRYSTAL

    expect_raises(Adamas::HIR::LoweringError, /must return ModuleReturnExplicitExpected/) do
      converter.lower_main(main)
      converter.flush_pending_functions
    end
  end

  it "accepts a forall result using the selected call binding" do
    converter, main = lower_module_return_contract_source(<<-CRYSTAL)
      class ModuleReturnForallExpected
      end

      module ModuleReturnForallOwner
        def self.identity(value : T) : T forall T
          value
        end
      end

      ModuleReturnForallOwner.identity(ModuleReturnForallExpected.new)
    CRYSTAL

    converter.lower_main(main)
    converter.flush_pending_functions
    converter.__test_module_return_types(
      "ModuleReturnForallOwner.identity",
    ).should contain("ModuleReturnForallExpected")
  end

  it "rejects a forall result that contradicts the selected call binding" do
    converter, main = lower_module_return_contract_source(<<-CRYSTAL)
      class ModuleReturnForallExpected
      end

      class ModuleReturnForallActual
      end

      module ModuleReturnForallOwner
        def self.bad(value : T) : T forall T
          ModuleReturnForallActual.new
        end
      end

      ModuleReturnForallOwner.bad(ModuleReturnForallExpected.new)
    CRYSTAL

    expect_raises(Adamas::HIR::LoweringError, /must return ModuleReturnForallExpected/) do
      converter.lower_main(main)
      converter.flush_pending_functions
    end
  end

  it "keeps an explicitly discarded Void result from adopting the body value type" do
    converter, main = lower_module_return_contract_source(<<-CRYSTAL)
      class ModuleReturnDiscardedValue
      end

      module ModuleReturnDiscardOwner
        def self.discard(value : ModuleReturnDiscardedValue) : Void
          value
        end
      end

      ModuleReturnDiscardOwner.discard(ModuleReturnDiscardedValue.new)
    CRYSTAL

    converter.lower_main(main)
    converter.flush_pending_functions
    return_types = converter.__test_module_return_types("ModuleReturnDiscardOwner.discard")
    return_types.should_not be_empty
    return_types.each { |return_type| return_type.should eq("Void") }
  end
end
