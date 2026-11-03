require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_deferred_path_constant_names : Array(String)
    @deferred_constant_inits.map do |entry|
      deferred_constant_full_name(entry.owner, entry.name)
    end
  end

  def __test_deferred_path_constant_type(name : String) : String?
    @constant_types[name]?.try { |type| get_type_name_from_ref(type) }
  end
end

private def register_deferred_path_constant_source(source : String) : {Adamas::HIR::AstToHir, Array(String)}
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true

  # Match the CLI's declaration census: names and class kinds are seeded from
  # the whole parsed root set before any declaration registration or main
  # lowering. Without this pass, a qualified path in lower_main can be treated
  # as an unresolved constant even though its module is registered below.
  top_level_type_names = Set(String).new
  top_level_class_kinds = {} of String => Bool
  program.roots.each do |root_id|
    case node = program.arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      name = String.new(node.name)
      top_level_type_names.add(name)
      top_level_class_kinds[name] = node.is_struct == true
    when Adamas::Compiler::Frontend::ModuleNode,
         Adamas::Compiler::Frontend::EnumNode,
         Adamas::Compiler::Frontend::AliasNode,
         Adamas::Compiler::Frontend::LibNode
      top_level_type_names.add(String.new(node.name))
    end
  end
  converter.seed_top_level_type_names(top_level_type_names)
  converter.seed_top_level_class_kinds(top_level_class_kinds.to_a)

  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = program.arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::AliasNode
      converter.register_alias(node)
    else
      main << root_id.index.to_u64
    end
  end

  # Registration queues deferred value initializers and gives them a provisional
  # Void type. Lower the declared module methods and then the normal main
  # initializer queue before asserting their inferred types. Retain the queue
  # names separately because lower_main consumes the queue.
  modules.each { |node| converter.lower_module(node) }
  scheduled_names = converter.__test_deferred_path_constant_names
  converter.lower_main(main)
  converter.flush_pending_functions
  {converter, scheduled_names}
end

describe "deferred PathNode constant aliases" do
  it "schedules qualified, absolute, and owner-relative value aliases but not type paths" do
    converter, entries = register_deferred_path_constant_source(<<-CRYSTAL)
      module DeferredPathAliasProbe
        def self.make : Int32
          65
        end

        module Values
          SOURCE = DeferredPathAliasProbe.make
        end

        QUALIFIED = DeferredPathAliasProbe::Values::SOURCE
        ABSOLUTE = ::DeferredPathAliasProbe::Values::SOURCE

        class DirectType
          def self.value : Int32
            66
          end
        end
        TYPE_ONLY = DeferredPathAliasProbe::DirectType

        module Nested
          module Reader
            RELATIVE = Values::SOURCE
          end
        end
      end
      CRYSTAL

    entries.count("DeferredPathAliasProbe::Values::SOURCE").should eq(1)
    entries.count("DeferredPathAliasProbe::QUALIFIED").should eq(1)
    entries.count("DeferredPathAliasProbe::ABSOLUTE").should eq(1)
    entries.count("DeferredPathAliasProbe::Nested::Reader::RELATIVE").should eq(1)
    entries.should_not contain("DeferredPathAliasProbe::TYPE_ONLY")

    [
      "DeferredPathAliasProbe::Values::SOURCE",
      "DeferredPathAliasProbe::QUALIFIED",
      "DeferredPathAliasProbe::ABSOLUTE",
      "DeferredPathAliasProbe::Nested::Reader::RELATIVE",
    ].each do |name|
      converter.__test_deferred_path_constant_type(name).should eq("Int32")
    end
  end

  it "preserves the full nullable union type through a qualified alias" do
    converter, entries = register_deferred_path_constant_source(<<-CRYSTAL)
      module DeferredPathUnionProbe
        def self.source : Int32?
          nil
        end

        SOURCE = DeferredPathUnionProbe.source
        ALIAS = DeferredPathUnionProbe::SOURCE
      end
      CRYSTAL

    entries.should contain("DeferredPathUnionProbe::SOURCE")
    entries.should contain("DeferredPathUnionProbe::ALIAS")
    converter.__test_deferred_path_constant_type("DeferredPathUnionProbe::SOURCE").not_nil!.split(" | ").sort.should eq(["Int32", "Nil"])
    converter.__test_deferred_path_constant_type("DeferredPathUnionProbe::ALIAS").not_nil!.split(" | ").sort.should eq(["Int32", "Nil"])
  end
end
