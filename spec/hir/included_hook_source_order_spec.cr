require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_enable_lazy_hook_registration : Nil
    @lazy_module_methods = true
  end

  def __test_hook_function(owner : String, method_name : String, arg_types : Array(TypeRef) = [] of TypeRef)
    name = mangle_function_name("#{owner}##{method_name}", arg_types)
    @module.function_by_name(name)
  end

  def __test_hook_function_type(owner : String, method_name : String, arg_types : Array(TypeRef)) : TypeRef?
    name = mangle_function_name("#{owner}##{method_name}", arg_types)
    @function_types[name]?
  end
end

private def lower_included_hook_source(source : String, lazy : Bool = false) : Adamas::HIR::AstToHir
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

  program.roots.each { |root_id| converter.record_source_declaration_order(arena[root_id], arena) }
  macros = [] of Adamas::Compiler::Frontend::MacroDefNode
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::MacroDefNode
      macros << node
    when Adamas::Compiler::Frontend::ModuleNode
      modules << node
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    else
      main << root_id.index.to_u64
    end
  end

  macros.each { |node| converter.register_macro(node) }
  modules.each { |node| converter.register_module(node) }
  converter.__test_enable_lazy_hook_registration if lazy
  classes.each { |node| converter.register_class(node) }
  classes.each { |node| converter.lower_class(node) } unless lazy
  modules.each { |node| converter.lower_module(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

private def hook_method_text(converter : Adamas::HIR::AstToHir, owner : String, method_name : String = "marker") : String
  function = converter.__test_hook_function(owner, method_name)
  function.should_not be_nil
  String.build { |io| function.not_nil!.to_s(io) }
end

private def included_hook_source_fixture : String
  <<-CRYSTAL
    module FirstHookSource
      macro included
        def marker : Int32
          65
        end
      end
    end

    module LastHookSource
      macro included
        def marker : Int32
          66
        end
      end
    end

    class HookHostAB
      include FirstHookSource
      include LastHookSource
    end

    class HookHostBA
      include LastHookSource
      include FirstHookSource
    end

    class HookDirectBefore
      def marker : Int32
        67
      end
      include LastHookSource
    end

    class HookDirectAfter
      include LastHookSource
      def marker : Int32
        68
      end
    end

    class HookGetterBefore
      def initialize(@marker : Int32)
      end
      getter marker : Int32
      include LastHookSource
    end

    class HookGetterAfter
      def initialize(@marker : Int32)
      end
      include LastHookSource
      getter marker : Int32
    end

    macro include_last_hook
      include LastHookSource
    end

    class HookClassMacroInclude
      def marker : Int32
        69
      end
      include_last_hook()
    end

    HookHostAB.new.marker
    HookHostBA.new.marker
    HookDirectBefore.new.marker
    HookDirectAfter.new.marker
    HookClassMacroInclude.new.marker
    HookGetterBefore.new(70).marker
    HookGetterAfter.new(71).marker
  CRYSTAL
end

describe "source order for included-hook members" do
  {false, true}.each do |lazy|
    it "uses include and class declaration order before publishing zero-arg bodies (lazy=#{lazy})" do
      converter = lower_included_hook_source(included_hook_source_fixture, lazy)

      hook_method_text(converter, "HookHostAB").should contain("literal 66")
      hook_method_text(converter, "HookHostBA").should contain("literal 65")
      hook_method_text(converter, "HookDirectBefore").should contain("literal 66")
      hook_method_text(converter, "HookDirectAfter").should contain("literal 68")
      hook_method_text(converter, "HookClassMacroInclude").should contain("literal 66")
      hook_method_text(converter, "HookGetterBefore").should contain("literal 66")

      getter_after = hook_method_text(converter, "HookGetterAfter")
      getter_after.should contain("field_get")
      getter_after.should contain("@marker")
      getter_after.should_not contain("literal 66")
    end
  end

  it "keeps applied generic included-hook signatures scoped to each include application" do
    converter = lower_included_hook_source(<<-CRYSTAL)
      module GenericTypedHook(T)
        macro included
          def typed_marker(value : T) : Int32
            65
          end
        end
      end

      class GenericTypedHookHost32
        include GenericTypedHook(Int32)
      end

      class GenericTypedHookHost64
        include GenericTypedHook(Int64)
      end

      GenericTypedHookHost32.new.typed_marker(0)
      GenericTypedHookHost64.new.typed_marker(0_i64)
    CRYSTAL

    i32 = converter.__test_hook_function(
      "GenericTypedHookHost32",
      "typed_marker",
      [Adamas::HIR::TypeRef::INT32],
    )
    i64 = converter.__test_hook_function(
      "GenericTypedHookHost64",
      "typed_marker",
      [Adamas::HIR::TypeRef::INT64],
    )
    i32.should_not be_nil
    i64.should_not be_nil
    converter.__test_hook_function_type(
      "GenericTypedHookHost32",
      "typed_marker",
      [Adamas::HIR::TypeRef::INT32],
    ).should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_hook_function_type(
      "GenericTypedHookHost64",
      "typed_marker",
      [Adamas::HIR::TypeRef::INT64],
    ).should eq(Adamas::HIR::TypeRef::INT32)
  end
end
