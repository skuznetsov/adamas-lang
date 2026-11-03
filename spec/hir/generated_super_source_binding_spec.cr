require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_bind_generated_super_source_target!(
    target_name : String,
    selected_def : Adamas::Compiler::Frontend::DefNode,
    selected_arena : Adamas::Compiler::Frontend::ArenaLike,
    lexical_owner : String,
  ) : Nil
    bind_generated_super_source_target!(target_name, selected_def, selected_arena, lexical_owner)
  end

  def __test_generated_super_source_registration_matches?(
    target_name : String,
    expected_def : Adamas::Compiler::Frontend::DefNode,
    expected_arena : Adamas::Compiler::Frontend::ArenaLike,
    expected_owner : String,
  ) : Bool
    @function_defs[target_name]?.try(&.same?(expected_def)) == true &&
      @function_def_arenas[target_name]?.try(&.same?(expected_arena)) == true &&
      function_namespace_override_for(target_name) == expected_owner
  end

  def __test_portable_generated_super_binding(
    target_prefix : String,
    source_definition : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Tuple(Bool, Bool, String, Array(String))
    candidates = @module.functions.select { |function| function.name.starts_with?(target_prefix) }
    raise "expected one generated super body for #{target_prefix}, got #{candidates.size}" unless candidates.size == 1

    function = candidates.first
    exact_definition = @function_defs[function.name]?.try(&.same?(source_definition)) == true
    exact_arena = @function_def_arenas[function.name]?.try(&.object_id) == source_arena.object_id
    parameter_types = function.params.map { |param| get_type_name_from_ref(param.type) }
    {
      exact_definition,
      exact_arena,
      get_type_name_from_ref(function.return_type),
      parameter_types,
    }
  end
end

private def lower_generated_super_binding_guard_fixture : Tuple(
  Adamas::HIR::AstToHir,
  Adamas::Compiler::Frontend::DefNode,
  Adamas::Compiler::Frontend::DefNode,
  Adamas::Compiler::Frontend::ArenaLike,
)
  source = <<-CRYSTAL
    module PortableSuperGuardBase
      def probe(value : Int32) : Int32
        value
      end
    end

    module PortableSuperGuardOther
      def probe(value : Int32) : Int32
        value
      end
    end
  CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true

  definitions = {} of String => Adamas::Compiler::Frontend::DefNode
  program.roots.each do |root_id|
    next unless node = arena[root_id].as?(Adamas::Compiler::Frontend::ModuleNode)

    converter.register_module(node)
    module_name = String.new(node.name)
    definition = node.body.not_nil!.compact_map do |member_id|
      arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
    end.find { |candidate| String.new(candidate.name) == "probe" }
    definitions[module_name] = definition.not_nil!
  end

  {
    converter,
    definitions["PortableSuperGuardBase"],
    definitions["PortableSuperGuardOther"],
    arena.as(Adamas::Compiler::Frontend::ArenaLike),
  }
end

private def lower_portable_generic_module_super_fixture : Tuple(
  Adamas::HIR::AstToHir,
  Adamas::Compiler::Frontend::DefNode,
  Adamas::Compiler::Frontend::ArenaLike,
  String,
)
  source = <<-CRYSTAL
    module PortableSuperGenericBase(T)
      class Payload
      end

      def value(x : T, payload : Payload) : Payload
        payload
      end
    end

    class PortableSuperProbe
      class Payload
      end

      include PortableSuperGenericBase(Int32)

      def value(x : Int32, payload : PortableSuperGenericBase::Payload)
        super
      end
    end
  CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  source_definition = nil.as(Adamas::Compiler::Frontend::DefNode?)
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      classes << node
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
      if String.new(node.name) == "PortableSuperGenericBase"
        source_definition = node.body.not_nil!.compact_map do |member_id|
          arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
        end.find { |definition| String.new(definition.name) == "value" }
      end
    end
  end

  classes.each { |node| converter.lower_class(node) }
  modules.each { |node| converter.lower_module(node) }
  converter.flush_pending_functions

  source_definition.should_not be_nil
  {
    converter,
    source_definition.not_nil!,
    arena.as(Adamas::Compiler::Frontend::ArenaLike),
    "PortableSuperProbe#value_super_from_",
  }
end

private def lower_portable_class_method_super_fixture : Tuple(
  Adamas::HIR::AstToHir,
  Adamas::Compiler::Frontend::DefNode,
  Adamas::Compiler::Frontend::ArenaLike,
  String,
)
  source = <<-CRYSTAL
    class PortableClassSuperBase
      def self.value(x : Int32) : Int32
        x
      end
    end

    class PortableClassSuperChild < PortableClassSuperBase
      def self.value(x : Int32)
        super
      end
    end
  CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  source_definition = nil.as(Adamas::Compiler::Frontend::DefNode?)
  program.roots.each do |root_id|
    if node = arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
      classes << node
      if String.new(node.name) == "PortableClassSuperBase"
        source_definition = node.body.not_nil!.compact_map do |member_id|
          arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
        end.find { |definition| String.new(definition.name) == "value" }
      end
    end
  end

  classes.each { |node| converter.lower_class(node) }
  converter.flush_pending_functions

  source_definition.should_not be_nil
  {
    converter,
    source_definition.not_nil!,
    arena.as(Adamas::Compiler::Frontend::ArenaLike),
    "PortableClassSuperChild.value_super_from_PortableClassSuperBase",
  }
end

describe "portable generated-super source binding" do
  it "binds a generic included-module super body to its exact Def and lexical types" do
    converter, source_definition, source_arena, target_prefix =
      lower_portable_generic_module_super_fixture

    exact_definition, exact_arena, return_type, parameter_types =
      converter.__test_portable_generated_super_binding(
        target_prefix, source_definition, source_arena,
      )

    exact_definition.should be_true
    exact_arena.should be_true
    return_type.should eq("PortableSuperGenericBase::Payload")
    parameter_types.size.should eq(3)
    parameter_types[1].should eq("Int32")
    parameter_types[2].should eq("PortableSuperGenericBase::Payload")
  end

  it "binds a generated class-method super body to its exact source Def and arena" do
    converter, source_definition, source_arena, target_prefix =
      lower_portable_class_method_super_fixture

    exact_definition, exact_arena, return_type, parameter_types =
      converter.__test_portable_generated_super_binding(
        target_prefix, source_definition, source_arena,
      )

    exact_definition.should be_true
    exact_arena.should be_true
    return_type.should eq("Int32")
    parameter_types.should contain("Int32")
  end

  it "allows idempotent exact registration and preserves it after owner conflicts" do
    converter, base_def, other_def, arena = lower_generated_super_binding_guard_fixture
    target_name = "PortableSuperGuardHost#probe_super_from_PortableSuperGuardBase$Int32"
    lexical_owner = "PortableSuperGuardBase"

    converter.__test_bind_generated_super_source_target!(target_name, base_def, arena, lexical_owner)
    converter.__test_bind_generated_super_source_target!(target_name, base_def, arena, lexical_owner)
    converter.__test_generated_super_source_registration_matches?(
      target_name, base_def, arena, lexical_owner,
    ).should be_true

    expect_raises(Adamas::HIR::LoweringError, /different source definition/) do
      converter.__test_bind_generated_super_source_target!(
        target_name, other_def, arena, "PortableSuperGuardOther",
      )
    end
    converter.__test_generated_super_source_registration_matches?(
      target_name, base_def, arena, lexical_owner,
    ).should be_true

    expect_raises(Adamas::HIR::LoweringError, /lexical owner changed/) do
      converter.__test_bind_generated_super_source_target!(
        target_name, base_def, arena, "PortableSuperGuardOther",
      )
    end
    converter.__test_generated_super_source_registration_matches?(
      target_name, base_def, arena, lexical_owner,
    ).should be_true
  end
end

# A generated class-method body keeps lexical names on Enum, while every
# occurrence of source `self`, including nullable self, denotes the receiver.
private def lower_generated_super_nullable_self_fixture
  source = <<-CRYSTAL
    abstract struct Enum
      def self.make(value : Int32) : self?
        return nil if value == 0
        new(value)
      end

      def self.build(value : Int32) : self
        make(value) || new(value)
      end
    end

    enum PortableNullableSuperDay
      Answer = 65

      def self.build(value : Int32) : self
        super(value)
      end
    end

    PortableNullableSuperDay.build(65)
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::EnumNode
      converter.register_enum(node)
    else
      main << root_id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
end

describe "generated super composite self annotations" do
  it "keeps nullable self on the runtime enum receiver" do
    lower_generated_super_nullable_self_fixture
  end
end
