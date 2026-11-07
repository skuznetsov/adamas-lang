require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def module_primitive_annotation_scope_converter(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/module_primitive_annotation_scope_spec.cr"},
  )
  converter.no_prelude = true
  program.roots.each do |root_id|
    node = arena[root_id]
    converter.register_module(node) if node.is_a?(Adamas::Compiler::Frontend::ModuleNode)
  end
  converter
end

private def module_primitive_family_call_converter(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      classes << node
    else
      main << root_id.index.to_u64
    end
  end

  classes.each { |node| converter.lower_class(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "module primitive annotation scope" do
  it "binds an instance-method annotation before a nested module early exit" do
    converter = module_primitive_annotation_scope_converter(<<-CRYSTAL)
      module PrimitiveScopeOuter
        module Ops
          @[Primitive(:object_id)]
          def instance_primitive : UInt64
          end

          def self.ordinary : UInt64
            17_u64
          end
        end
      end
    CRYSTAL

    converter.module.primitive_for("PrimitiveScopeOuter::Ops#instance_primitive").should eq("object_id")
    converter.module.primitive_for("PrimitiveScopeOuter::Ops.ordinary").should be_nil
  end

  it "drops a pending primitive when an unrelated module member intervenes" do
    converter = module_primitive_annotation_scope_converter(<<-CRYSTAL)
      module PrimitiveScopeInterrupted
        @[Primitive(:object_id)]
        @@state : Int32

        def self.ordinary : UInt64
          19_u64
        end
      end
    CRYSTAL

    converter.module.primitive_for("PrimitiveScopeInterrupted.ordinary").should be_nil
  end

  it "restores annotation state at module scope exit" do
    converter = module_primitive_annotation_scope_converter(<<-CRYSTAL)
      module PrimitiveScopeDangling
        @[Primitive(:object_id)]
        @@state : Int32
      end

      module PrimitiveScopeNext
        def self.ordinary : UInt64
          23_u64
        end
      end
    CRYSTAL

    converter.module.primitive_for("PrimitiveScopeNext.ordinary").should be_nil
  end

  it "emits an ordinary sibling overload call when another overload is primitive" do
    converter = module_primitive_family_call_converter(<<-CRYSTAL)
      class PrimitiveFamilySibling
        @[Primitive(:object_id)]
        def object_id : UInt64
        end

        def object_id(value : Int32) : UInt64
          41_u64
        end
      end

      PrimitiveFamilySibling.new.object_id(1)
    CRYSTAL

    main = converter.module.function_by_name("__adamas_main")
    main.should_not be_nil
    calls = main.not_nil!.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
    sibling_call = calls.find { |call| call.method_name.includes?("#object_id$Int32") }
    sibling_call.should_not be_nil
    converter.module.has_function_with_body?("PrimitiveFamilySibling#object_id$Int32").should be_true
  end

  it "lowers an empty ordinary sibling body when another overload is primitive" do
    converter = module_primitive_family_call_converter(<<-CRYSTAL)
      class PrimitiveFamilyEmptySibling
        @[Primitive(:object_id)]
        def object_id : UInt64
        end

        def object_id(value : Int32) : Nil
        end
      end

      PrimitiveFamilyEmptySibling.new.object_id(1)
    CRYSTAL

    main = converter.module.function_by_name("__adamas_main")
    main.should_not be_nil
    calls = main.not_nil!.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
    sibling_call = calls.find { |call| call.method_name.includes?("#object_id$Int32") }
    sibling_call.should_not be_nil
    converter.module.has_function_with_body?("PrimitiveFamilyEmptySibling#object_id$Int32").should be_true
  end
end
