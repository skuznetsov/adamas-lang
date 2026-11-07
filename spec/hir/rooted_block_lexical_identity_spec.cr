require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_rooted_block_source(source : String)
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
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end



private def rooted_block_identity_declarations
  <<-CRYSTAL
    class Path
    end

    module Scope
      class Path
      end

      alias RootPathClass = ::Path.class
      alias RootPathClassAgain = RootPathClass
      alias LexicalPathClass = Path.class

      class Owner
        def self.lexical_class(&block : -> Path.class)
          yield
          65
        end

        def self.rooted_class(&block : -> ::Path.class)
          yield
          66
        end

        def self.mixed(&block : -> Path | ::Path.class)
          yield
          67
        end

        def self.lexical_alias(&block : -> LexicalPathClass)
          yield
          70
        end

        def self.rooted_alias_again(&block : -> RootPathClassAgain)
          yield
          71
        end

        def self.rooted_alias(&block : -> RootPathClass)
          yield
          68
        end
      end
    end

    CRYSTAL
end

describe "actual rooted and lexical callback result identity" do
  it "accepts an explicit root class" do
    lower_rooted_block_source(rooted_block_identity_declarations + "\nScope::Owner.rooted_class { ::Path }\n")
  end

  it "accepts the lexical shadow class" do
    lower_rooted_block_source(rooted_block_identity_declarations + "\nScope::Owner.lexical_class { Scope::Path }\n")
  end

  it "accepts a root class named at the top level" do
    lower_rooted_block_source(rooted_block_identity_declarations + "\nScope::Owner.rooted_class { Path }\n")
  end

  it "accepts a rooted metaclass alias" do
    lower_rooted_block_source(rooted_block_identity_declarations + "\nScope::Owner.rooted_alias { ::Path }\n")
  end

  it "accepts a lexical metaclass alias" do
    lower_rooted_block_source(rooted_block_identity_declarations + "\nScope::Owner.lexical_alias { Scope::Path }\n")
  end

  it "accepts a rooted metaclass alias chain" do
    lower_rooted_block_source(rooted_block_identity_declarations + "\nScope::Owner.rooted_alias_again { ::Path }\n")
  end

  it "rejects the root class for a lexical restriction" do
    expect_raises(Adamas::HIR::LoweringError, "expected block passed to") do
      lower_rooted_block_source(rooted_block_identity_declarations + "\nScope::Owner.lexical_class { ::Path }\n")
    end
  end

  it "rejects a bare top level root for a lexical restriction" do
    expect_raises(Adamas::HIR::LoweringError, "expected block passed to") do
      lower_rooted_block_source(rooted_block_identity_declarations + "\nScope::Owner.lexical_class { Path }\n")
    end
  end

  it "rejects a lexical shadow for a rooted alias" do
    expect_raises(Adamas::HIR::LoweringError, "expected block passed to") do
      lower_rooted_block_source(rooted_block_identity_declarations + "\nScope::Owner.rooted_alias { Scope::Path }\n")
    end
  end

  it "rejects the root class for a lexical alias" do
    expect_raises(Adamas::HIR::LoweringError, "expected block passed to") do
      lower_rooted_block_source(rooted_block_identity_declarations + "\nScope::Owner.lexical_alias { ::Path }\n")
    end
  end

end
