require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_registered_constant_type_name(name : String) : String?
    @constant_types[name]?.try { |type| get_type_name_from_ref(type) }
  end

  def __test_method_source_arena(
    definition : Adamas::Compiler::Frontend::DefNode,
    fallback : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::Compiler::Frontend::ArenaLike
    source_method_declaration_arena(definition, fallback)
  end

  def __test_lower_defaulted_method_param_type(
    owner : String,
    definition : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
    ambient_owner : String,
    active_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : String?
    previous_arena = @arena
    previous_class = @current_class
    previous_namespace = @current_namespace_override
    @arena = active_arena
    @current_class = ambient_owner
    @current_namespace_override = nil
    begin
      base_name = "#{owner}#initialize"
      set_function_def_entry(base_name, definition, false)
      set_function_def_arena(base_name, source_arena)
      first_new_function = @module.functions.size
      lower_method(owner, @class_info[owner], definition)
      index = first_new_function
      while index < @module.functions.size
        function = @module.functions.unsafe_fetch(index)
        if function.name.starts_with?(base_name)
          if parameter = function.params.last?
            return get_type_name_from_ref(parameter.type)
          end
          return nil
        end
        index += 1
      end
      nil
    ensure
      @arena = previous_arena
      @current_class = previous_class
      @current_namespace_override = previous_namespace
    end
  end
end

private def parse_registered_default_source(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program
end

private def registered_default_class(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  roots : Array(Adamas::Compiler::Frontend::ExprId),
  name : String,
) : Adamas::Compiler::Frontend::ClassNode
  roots.each do |root|
    if node = arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
      return node if String.new(node.name) == name
    end
  end
  raise "missing class #{name}"
end

private def registered_default_initializer(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  owner : Adamas::Compiler::Frontend::ClassNode,
) : Adamas::Compiler::Frontend::DefNode
  body = owner.body || raise "missing class body"
  body.each do |expr_id|
    if node = arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
      return node if String.new(node.name) == "initialize"
    end
  end
  raise "missing initialize definition"
end

private def registered_default_same_arena_fixture
  source = <<-CRYSTAL
    class DefaultOwner
      DEFAULT = "owner"

      def initialize(value = DEFAULT)
      end
    end

    class CallerScope
      DEFAULT = 73
    end
  CRYSTAL
  program = parse_registered_default_source(source)
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    main_arenas: [arena] of Adamas::Compiler::Frontend::ArenaLike,
  )
  converter.no_prelude = true
  owner = registered_default_class(arena, program.roots, "DefaultOwner")
  caller = registered_default_class(arena, program.roots, "CallerScope")
  converter.register_class(owner)
  converter.register_class(caller)
  {converter, arena, registered_default_initializer(arena, owner)}
end

private def registered_default_split_arena_fixture
  owner_source = <<-CRYSTAL
    class DefaultOwner
      DEFAULT = "owner"

      def initialize(value = DEFAULT)
      end
    end
  CRYSTAL
  caller_source = <<-CRYSTAL
    class CallerScope
      DEFAULT = 73

      def initialize(value = 73)
      end
    end
  CRYSTAL
  owner_program = parse_registered_default_source(owner_source)
  caller_program = parse_registered_default_source(caller_source)
  owner_arena = owner_program.arena
  caller_arena = caller_program.arena
  converter = Adamas::HIR::AstToHir.new(
    owner_arena,
    sources_by_arena: {
      owner_arena.object_id.to_u64 => owner_source,
      caller_arena.object_id.to_u64 => caller_source,
    },
    main_arenas: [owner_arena, caller_arena] of Adamas::Compiler::Frontend::ArenaLike,
  )
  converter.no_prelude = true
  owner = registered_default_class(owner_arena, owner_program.roots, "DefaultOwner")
  caller = registered_default_class(caller_arena, caller_program.roots, "CallerScope")
  converter.arena = owner_arena
  converter.register_class(owner)
  converter.arena = caller_arena
  converter.register_class(caller)
  definition = registered_default_initializer(owner_arena, owner)
  caller_definition = registered_default_initializer(caller_arena, caller)
  {converter, owner_arena, caller_arena, definition, caller_definition}
end

describe "default parameter inference source context" do
  it "uses the declaring class constant when the caller has a same-named constant" do
    converter, arena, definition = registered_default_same_arena_fixture
    converter.__test_registered_constant_type_name("DefaultOwner::DEFAULT").should eq("String")
    converter.__test_registered_constant_type_name("CallerScope::DEFAULT").should eq("Int32")

    converter.__test_lower_defaulted_method_param_type(
      "DefaultOwner", definition, arena, "DefaultOwner", arena,
    ).should eq("String")
  end

  it "does not infer the default through the ambient caller's lexical constants" do
    converter, arena, definition = registered_default_same_arena_fixture
    converter.__test_registered_constant_type_name("DefaultOwner::DEFAULT").should eq("String")
    converter.__test_registered_constant_type_name("CallerScope::DEFAULT").should eq("Int32")

    converter.__test_lower_defaulted_method_param_type(
      "DefaultOwner", definition, arena, "CallerScope", arena,
    ).should eq("String")
  end

  it "uses the exact registered Def arena before interpreting its default ExprId" do
    converter, owner_arena, caller_arena, definition, caller_definition = registered_default_split_arena_fixture
    owner_default = definition.params.not_nil![0].default_value.not_nil!
    caller_default = caller_definition.params.not_nil![0].default_value.not_nil!
    owner_default.index.should eq(caller_default.index)
    owner_arena[owner_default].should be_a(Adamas::Compiler::Frontend::IdentifierNode)
    caller_arena[caller_default].should be_a(Adamas::Compiler::Frontend::NumberNode)
    converter.__test_method_source_arena(definition, caller_arena).same?(owner_arena).should be_true

    # Keep lexical lookup fixed to DefaultOwner. Only the active arena is
    # adversarial: ExprIds are arena-relative, and the same index in the caller
    # arena denotes the numeric literal 73 rather than the owner's constant.
    converter.__test_lower_defaulted_method_param_type(
      "DefaultOwner", definition, owner_arena, "DefaultOwner", caller_arena,
    ).should eq("String")
  end
end
