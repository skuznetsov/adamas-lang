require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __module_root_test_has_registered_type?(name : String) : Bool
    @class_info.has_key?(name) || @module_defs.has_key?(name)
  end

  def __module_root_test_registered_class_names : Array(String)
    @class_info.keys
  end

  def __module_root_test_has_registered_function?(name : String) : Bool
    @function_defs.has_key?(name)
  end

  def __module_root_test_has_registered_function_type?(name : String) : Bool
    @function_types.has_key?(name)
  end

  def __module_root_test_has_registered_ivar?(owner : String, name : String) : Bool
    @class_info[owner]?.try { |info| info.ivars.any? { |ivar| ivar.name == name } } || false
  end

  def __module_root_test_registered_ivars_for?(owner : String) : Array(String)
    @class_info[owner]?.try { |info| info.ivars.map(&.name) } || [] of String
  end

  def __module_root_test_registered_function_types_for?(prefix : String) : Array(String)
    @function_types.keys.select(&.starts_with?(prefix))
  end

  def __module_root_test_resolve_class_name_in_context(name : String, current : String?) : String
    old_current = @current_class
    old_override = @current_namespace_override
    @current_class = current
    @current_namespace_override = nil
    begin
      resolve_class_name_in_context(name)
    ensure
      @current_class = old_current
      @current_namespace_override = old_override
    end
  end
end

private def register_module_absolute_class_fixture(source : String) : Adamas::HIR::AstToHir
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  program = parser.parse_program
  arena = parser.arena
  converter = Adamas::HIR::AstToHir.new(arena)
  converter.arena = arena

  # The compiler seeds this index from the same top-level declarations before
  # registration. Keep this focused registrar probe in that production order.
  converter.seed_top_level_type_names([
    "Thread",
    "AbsoluteThreadMacroOwner",
    "NestedThreadShadowControl",
    "AbsoluteThreadClassMacroOwner",
    "RelativeThreadClassShadowControl",
  ])

  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end

  converter
end

describe "absolute class declarations in module macro expansions" do
  it "keeps an absolute root class at the root and preserves real nested shadowing" do
    converter = register_module_absolute_class_fixture(<<-CRYSTAL)
      class Thread
        def self.current
        end
      end

      module AbsoluteThreadMacroOwner
        macro declare_root_thread
          class ::Thread
            def self.current
            end
          end
        end

        declare_root_thread
      end

      module NestedThreadShadowControl
        class Thread
          def self.current
          end
        end
      end
    CRYSTAL

    converter.__module_root_test_registered_class_names.should contain("Thread")
    converter.__module_root_test_has_registered_type?("AbsoluteThreadMacroOwner::Thread").should be_false
    converter.__module_root_test_has_registered_function?("Thread.current").should be_true
    converter.__module_root_test_has_registered_function?("AbsoluteThreadMacroOwner::Thread.current").should be_false
    converter.__module_root_test_resolve_class_name_in_context("Thread", "AbsoluteThreadMacroOwner").should eq("Thread")
    converter.__module_root_test_resolve_class_name_in_context("Thread", "NestedThreadShadowControl").should eq("NestedThreadShadowControl::Thread")
  end

end
