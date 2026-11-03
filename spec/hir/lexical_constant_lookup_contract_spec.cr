require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_lexical_constant_contract(source : String) : Adamas::HIR::AstToHir
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

  top_level_type_names = Set(String).new
  top_level_class_kinds = {} of String => Bool
  program.roots.each do |root_id|
    case node = arena[root_id]
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

  # Mirror the CLI's constant pre-scan: simple root literals are registered
  # before type bodies, while other root names are reserved for later lookup.
  simple_pre_scan_constant = ->(value_id : Adamas::Compiler::Frontend::ExprId) do
    value_node = arena[value_id]
    value_node.is_a?(Adamas::Compiler::Frontend::NumberNode) ||
      value_node.is_a?(Adamas::Compiler::Frontend::BoolNode) ||
      value_node.is_a?(Adamas::Compiler::Frontend::CharNode)
  end
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ConstantNode
      if simple_pre_scan_constant.call(node.value)
        converter.register_constant(node)
      else
        converter.pre_scan_constant_name(node)
      end
    when Adamas::Compiler::Frontend::AssignNode
      target = arena[node.target]
      if target.is_a?(Adamas::Compiler::Frontend::ConstantNode)
        if simple_pre_scan_constant.call(node.value)
          converter.register_constant_value(String.new(target.name), node.value, arena)
        else
          converter.pre_scan_constant_name(String.new(target.name))
        end
      end
    end
  end

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
    when Adamas::Compiler::Frontend::EnumNode
      converter.register_enum(node)
    when Adamas::Compiler::Frontend::AliasNode
      converter.register_alias(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root_id.index.to_u64
    end
  end

  # The CLI's full constant-registration pass follows top-level type
  # registration and precedes lowering class, module, and method bodies.
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ConstantNode
      converter.register_constant(node)
    when Adamas::Compiler::Frontend::AssignNode
      target = arena[node.target]
      if target.is_a?(Adamas::Compiler::Frontend::ConstantNode)
        converter.register_constant_value(String.new(target.name), node.value, arena)
      end
    end
  end

  classes.each { |node| converter.lower_class(node) }
  modules.each { |node| converter.lower_module(node) }
  program.roots.each do |root_id|
    node = arena[root_id]
    converter.lower_def(node) if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  converter.lower_main(main) unless main.empty?
  converter.flush_pending_functions
  converter
end

private def lexical_constant_classvar_reads(converter : Adamas::HIR::AstToHir) : Array(Tuple(String, String))
  converter.module.functions.flat_map(&.blocks).flat_map(&.instructions).compact_map do |instruction|
    instruction.as?(Adamas::HIR::ClassVarGet).try do |get|
      {get.class_name, get.var_name}
    end
  end
end

private def lexical_constant_literals(converter : Adamas::HIR::AstToHir) : Array(Adamas::HIR::Literal)
  converter.module.functions.flat_map(&.blocks).flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Literal))
end

describe "lexical constant lookup contract" do
  it "emits the defining module's constant read for an included body" do
    converter = lower_lexical_constant_contract(<<-CRYSTAL)
      module LexicalOwner
        VALUE = 65
        def read_value : Int32
          VALUE
        end
      end

      class Includer
        VALUE = 66
        include LexicalOwner
      end

      Includer.new.read_value
    CRYSTAL

    reads = lexical_constant_classvar_reads(converter).select { |read| read[1] == "VALUE" }
    reads.should contain({"LexicalOwner", "VALUE"})
    reads.should_not contain({"Includer", "VALUE"})
  end

  it "commits a qualified path to the declaring module namespace" do
    converter = lower_lexical_constant_contract(<<-CRYSTAL)
      module LexicalOwner
        module Nested
          VALUE = 65
        end

        def read_value : Int32
          Nested::VALUE
        end
      end

      class Includer
        module Nested
          VALUE = 66
        end
        include LexicalOwner
      end

      Includer.new.read_value
    CRYSTAL

    reads = lexical_constant_classvar_reads(converter).select { |read| read[1] == "VALUE" }
    reads.should contain({"LexicalOwner::Nested", "VALUE"})
    reads.should_not contain({"Includer::Nested", "VALUE"})
  end

  it "keeps an inherited method's parent constant and the explicit root path" do
    inherited = lower_lexical_constant_contract(<<-CRYSTAL)
      class Parent
        VALUE = 65
        def read_value : Int32
          VALUE
        end
      end

      class Child < Parent
        VALUE = 66
      end

      Child.new.read_value
    CRYSTAL
    parent_reads = lexical_constant_classvar_reads(inherited).select { |read| read[1] == "VALUE" }
    parent_reads.should contain({"Parent", "VALUE"})
    parent_reads.should_not contain({"Child", "VALUE"})

    rooted = lower_lexical_constant_contract(<<-CRYSTAL)
      ROOT_VALUE = 65
      module LexicalOwner
        ROOT_VALUE = 66
        def self.read_value : Int32
          ::ROOT_VALUE
        end
      end

      LexicalOwner.read_value
    CRYSTAL
    lexical_constant_classvar_reads(rooted).should contain({"Object", "ROOT_VALUE"})
  end

  it "emits a literal for an absolute enum member and a read for generic T::VALUE" do
    enum_converter = lower_lexical_constant_contract(<<-CRYSTAL)
      enum RootedColor : Int32
        Amber = 65
      end

      ::RootedColor::Amber
    CRYSTAL
    lexical_constant_literals(enum_converter).map(&.int_value).should contain(65_i64)

    generic_converter = lower_lexical_constant_contract(<<-CRYSTAL)
      class LexicalConstantTag
        VALUE = 65
      end

      class GenericConstantReader(T)
        def self.read : Int32
          T::VALUE
        end
      end

      GenericConstantReader(LexicalConstantTag).read
    CRYSTAL
    lexical_constant_classvar_reads(generic_converter).should contain({"LexicalConstantTag", "VALUE"})
  end

  it "rejects used missing bare, qualified, and absolute paths with their exact lowering detail" do
    expect_raises(Adamas::HIR::LoweringError, "undefined constant ONLY_ON_INCLUDER") do
      lower_lexical_constant_contract(<<-CRYSTAL)
        module LexicalOwner
          def read_value : Int32
            ONLY_ON_INCLUDER
          end
        end

        class Includer
          ONLY_ON_INCLUDER = 65
          include LexicalOwner
        end

        Includer.new.read_value
      CRYSTAL
    end

    expect_raises(Adamas::HIR::LoweringError, "undefined constant AbsentNested::VALUE") do
      lower_lexical_constant_contract(<<-CRYSTAL)
        module QualifiedMissingOwner
          def self.read : Int32
            AbsentNested::VALUE
          end
        end

        QualifiedMissingOwner.read
      CRYSTAL
    end

    expect_raises(Adamas::HIR::LoweringError, "undefined constant ::AbsoluteMissingOwner::VALUE") do
      lower_lexical_constant_contract("::AbsoluteMissingOwner::VALUE")
    end
  end
end
