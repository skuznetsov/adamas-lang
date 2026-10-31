require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_class_instance_method_lookup(source : String) : Adamas::HIR::AstToHir
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
  converter.no_prelude = true
  converter.arena = arena

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      classes << node
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
    else
      main << root_id.index.to_u64
    end
  end

  classes.each { |node| converter.lower_class(node) }
  modules.each { |node| converter.lower_module(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "class and instance method separator lookup" do
  it "selects inherited dotted methods, instance methods, and registered extend-self aliases" do
    converter = lower_class_instance_method_lookup(<<-CRYSTAL)
      class SeparatorLookupRoot
        def self.probe : Int32
          65
        end
      end

      class SeparatorLookupChild < SeparatorLookupRoot
        def probe : Int32
          66
        end
      end

      module SeparatorLookupExport
        extend self

        def exported_probe : Int32
          67
        end
      end

      SeparatorLookupChild.probe
      SeparatorLookupChild.new.probe
      SeparatorLookupExport.exported_probe
    CRYSTAL

    main = converter.module.function_by_name("__adamas_main")
    main.should_not be_nil
    calls = main.not_nil!.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))

    class_call = calls.find { |call| call.method_name.ends_with?(".probe") }
    class_call.should_not be_nil
    class_call.not_nil!.method_name.should contain("SeparatorLookupChild.")

    instance_call = calls.find { |call| call.method_name.ends_with?("#probe") }
    instance_call.should_not be_nil
    instance_call.not_nil!.method_name.should start_with("SeparatorLookupChild#")

    exported_call = calls.find { |call| call.method_name.ends_with?(".exported_probe") }
    exported_call.should_not be_nil
    converter.module.has_function_with_body?("SeparatorLookupExport.exported_probe").should be_true

    inherited_target = converter.module.function_by_name("SeparatorLookupChild.probe")
    inherited_target.should_not be_nil
    inherited_target.not_nil!.blocks.flat_map(&.instructions).should_not be_empty
  end
end
