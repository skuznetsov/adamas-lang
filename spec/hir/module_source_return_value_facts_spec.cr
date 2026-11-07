require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_module_source_return_packet(prefix : String) : Tuple(Array({String, Bool}), Bool, Int32)
    candidates = @module.functions.select do |function|
      (function.name == prefix || function.name.starts_with?("#{prefix}$")) &&
        !function.source_return_value_facts.nil?
    end
    raise "expected one published source return for #{prefix}, got #{candidates.size}" unless candidates.size == 1

    function = candidates.first
    facts = function.source_return_value_facts || raise "missing source return facts for #{function.name}"
    definition = @function_defs[function.name]?
    declaration_arena = @function_def_arenas[function.name]?
    exact_owner = if definition && declaration_arena
                    function.source_return_definition_id == definition.object_id.to_u64 &&
                      function.source_return_arena_key == arena_map_key(declaration_arena)
                  else
                    false
                  end
    rendered = facts.map { |(type, literal)| {get_type_name_from_ref(type), literal} }
    return_count = function.blocks.count { |block| block.terminator.is_a?(Adamas::HIR::Return) }
    {rendered, exact_owner, return_count}
  end
end

private def module_source_return_packet_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class ModuleSourceFactsLeft
    end

    class ModuleSourceFactsRight
    end

    class ModuleSourceFactsMixed
    end

    module ModuleSourceFactsFactory
      def self.implicit(flag : Bool) : ModuleSourceFactsLeft | ModuleSourceFactsRight
        if flag
          ModuleSourceFactsLeft.new
        else
          ModuleSourceFactsRight.new
        end
      end

      def self.explicit(flag : Bool) : ModuleSourceFactsLeft | ModuleSourceFactsRight
        if flag
          return ModuleSourceFactsLeft.new
        end
        return ModuleSourceFactsRight.new
      end

      def self.implicit_mixed(flag : Bool) : ModuleSourceFactsMixed.class | ModuleSourceFactsMixed
        if flag
          ModuleSourceFactsMixed
        else
          ModuleSourceFactsMixed.new
        end
      end

      def self.explicit_mixed(flag : Bool) : ModuleSourceFactsMixed.class | ModuleSourceFactsMixed
        if flag
          return ModuleSourceFactsMixed
        end
        return ModuleSourceFactsMixed.new
      end
    end

    ModuleSourceFactsFactory.implicit(true)
    ModuleSourceFactsFactory.explicit(false)
    ModuleSourceFactsFactory.implicit_mixed(true)
    ModuleSourceFactsFactory.explicit_mixed(false)
  CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/module_source_return_facts_packet_spec.cr"},
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
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "module source return ownership packet" do
  it "publishes both implicit instance-union exits under the exact definition and arena" do
    converter = module_source_return_packet_converter
    facts, exact_owner, return_count = converter.__test_module_source_return_packet(
      "ModuleSourceFactsFactory.implicit",
    )

    facts.size.should eq(2)
    facts.should contain({"ModuleSourceFactsLeft", false})
    facts.should contain({"ModuleSourceFactsRight", false})
    exact_owner.should be_true
    return_count.should be > 0
  end

  it "collects every explicit return exit under the exact definition and arena" do
    converter = module_source_return_packet_converter
    facts, exact_owner, return_count = converter.__test_module_source_return_packet(
      "ModuleSourceFactsFactory.explicit",
    )

    facts.size.should eq(2)
    facts.should contain({"ModuleSourceFactsLeft", false})
    facts.should contain({"ModuleSourceFactsRight", false})
    exact_owner.should be_true
    return_count.should be >= 2
  end

  it "retains both kinds for implicit mixed class and instance exits" do
    converter = module_source_return_packet_converter
    facts, exact_owner, return_count = converter.__test_module_source_return_packet(
      "ModuleSourceFactsFactory.implicit_mixed",
    )

    facts.size.should eq(2)
    facts.should contain({"ModuleSourceFactsMixed", false})
    facts.should contain({"ModuleSourceFactsMixed", true})
    exact_owner.should be_true
    return_count.should be > 0
  end

  it "retains both kinds for explicit mixed class and instance exits" do
    converter = module_source_return_packet_converter
    facts, exact_owner, return_count = converter.__test_module_source_return_packet(
      "ModuleSourceFactsFactory.explicit_mixed",
    )

    facts.size.should eq(2)
    facts.should contain({"ModuleSourceFactsMixed", false})
    facts.should contain({"ModuleSourceFactsMixed", true})
    exact_owner.should be_true
    return_count.should be >= 2
  end
end
