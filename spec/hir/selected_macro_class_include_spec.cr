require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_selected_include_register(source : String) : Nil
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    set_source_for_arena(program.arena, source)
    with_arena(program.arena) do
      program.roots.each do |id|
        case node = program.arena[id]
        when Adamas::Compiler::Frontend::ModuleNode
          register_module(node)
        when Adamas::Compiler::Frontend::ClassNode
          register_class(node)
        else
          raise "unexpected selected-include fixture root #{node.class}"
        end
      end
    end
  end

  def __test_selected_include_modules(owner : String) : Array(String)
    (@class_included_modules[owner]? || [] of String).dup
  end

  def __test_selected_include_exact_origin?(owner : String, method : String, source_owner : String) : Bool
    origin = find_included_module_def_origin_for_owner(
      owner, method, 0, false, respect_direct_declarations: false,
    )
    return false unless origin && origin[2] == source_owner
    selected = lookup_function_def_for_call("#{owner}##{method}", 0, false, [] of TypeRef)
    return false unless selected && selected[1].same?(origin[0])
    source_arena = registered_arena_for_def(selected[1])
    !source_arena.nil? && source_arena.same?(origin[1])
  end

  def __test_selected_include_registered_method?(owner : String, method : String) : Bool
    selected = lookup_function_def_for_call("#{owner}##{method}", 0, false, [] of TypeRef)
    return false unless selected
    source_arena = registered_arena_for_def(selected[1])
    entry_arena = @function_def_arenas[selected[0]]?
    !source_arena.nil? && !entry_arena.nil? && source_arena.same?(entry_arena)
  end

  def __test_selected_include_binding(owner : String, module_base : String, param : String) : TypeRef?
    bindings = included_module_type_param_map(owner, module_base)
    return nil unless bindings
    value = bindings[param]?
    return nil unless value
    with_isolated_type_param_map(bindings) { canonical_bound_type_ref(value) }
  end
end

private def selected_macro_class_include_fixture(*sources : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
  program = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(program.arena)
  converter.no_prelude = true
  sources.each { |source| converter.__test_selected_include_register(source) }
  converter
end

private def selected_macro_class_include_modules : String
  <<-CRYSTAL
    module SelectedBranchGood
      def marker : Int32
        65
      end
    end
    module SelectedBranchOther
      def marker : Int32
        66
      end
    end
    module SelectedBranchPoison
      @poison : Int32
      def initialize(@poison : Int32)
      end
      def forbidden : Int32
        @poison
      end
    end
  CRYSTAL
end

describe "includes emitted by selected class macro branches" do
  it "keeps the direct include control and exact module arena" do
    converter = selected_macro_class_include_fixture(selected_macro_class_include_modules, <<-CRYSTAL)
      class SelectedBranchOwner
        include SelectedBranchGood
      end
    CRYSTAL
    converter.__test_selected_include_modules("SelectedBranchOwner").should eq(["SelectedBranchGood"])
    converter.__test_selected_include_exact_origin?("SelectedBranchOwner", "marker", "SelectedBranchGood").should be_true
  end

  it "registers only the active THEN include" do
    converter = selected_macro_class_include_fixture(selected_macro_class_include_modules, <<-CRYSTAL)
      class SelectedBranchOwner
        {% if true %}
          include SelectedBranchGood
        {% else %}
          include SelectedBranchPoison
        {% end %}
      end
    CRYSTAL
    converter.__test_selected_include_modules("SelectedBranchOwner").should eq(["SelectedBranchGood"])
    converter.__test_selected_include_exact_origin?("SelectedBranchOwner", "marker", "SelectedBranchGood").should be_true
    converter.class_info["SelectedBranchOwner"].ivars.map(&.name).should_not contain("@poison")
  end

  it "registers only the active ELSE include" do
    converter = selected_macro_class_include_fixture(selected_macro_class_include_modules, <<-CRYSTAL)
      class SelectedBranchOwner
        {% if false %}
          include SelectedBranchPoison
        {% else %}
          include SelectedBranchOther
        {% end %}
      end
    CRYSTAL
    converter.__test_selected_include_modules("SelectedBranchOwner").should eq(["SelectedBranchOther"])
    converter.__test_selected_include_exact_origin?("SelectedBranchOwner", "marker", "SelectedBranchOther").should be_true
    converter.class_info["SelectedBranchOwner"].ivars.map(&.name).should_not contain("@poison")
  end

  it "does not publish an excluded module, method, or ivar" do
    converter = selected_macro_class_include_fixture(selected_macro_class_include_modules, <<-CRYSTAL)
      class SelectedBranchOwner
        {% if false %}
          include SelectedBranchPoison
        {% end %}
      end
    CRYSTAL
    converter.__test_selected_include_modules("SelectedBranchOwner").should be_empty
    converter.__test_selected_include_registered_method?("SelectedBranchOwner", "forbidden").should be_false
    converter.class_info["SelectedBranchOwner"].ivars.map(&.name).should_not contain("@poison")
  end

  it "registers an include in a nested selected ELSE branch" do
    converter = selected_macro_class_include_fixture(selected_macro_class_include_modules, <<-CRYSTAL)
      class SelectedBranchOwner
        {% if true %}
          {% if false %}
            include SelectedBranchPoison
          {% else %}
            include SelectedBranchGood
          {% end %}
        {% else %}
          include SelectedBranchPoison
        {% end %}
      end
    CRYSTAL
    converter.__test_selected_include_modules("SelectedBranchOwner").should eq(["SelectedBranchGood"])
    converter.__test_selected_include_exact_origin?("SelectedBranchOwner", "marker", "SelectedBranchGood").should be_true
  end

  it "registers an include in a selected ELSE then nested THEN branch" do
    converter = selected_macro_class_include_fixture(selected_macro_class_include_modules, <<-CRYSTAL)
      class SelectedBranchOwner
        {% if false %}
          include SelectedBranchPoison
        {% else %}
          {% if true %}
            include SelectedBranchOther
          {% else %}
            include SelectedBranchPoison
          {% end %}
        {% end %}
      end
    CRYSTAL
    converter.__test_selected_include_modules("SelectedBranchOwner").should eq(["SelectedBranchOther"])
    converter.__test_selected_include_exact_origin?("SelectedBranchOwner", "marker", "SelectedBranchOther").should be_true
  end

  it "imports the included initializer layout and its exact source definition" do
    converter = selected_macro_class_include_fixture(<<-CRYSTAL)
      module SelectedBranchInitializer
        @marker : Int32
        def initialize
          @marker = 69
        end
        def marker : Int32
          @marker
        end
      end
      class SelectedBranchOwner
        {% if true %}
          include SelectedBranchInitializer
        {% end %}
      end
    CRYSTAL
    fields = converter.class_info["SelectedBranchOwner"].ivars.select { |field| field.name == "@marker" }
    fields.size.should eq(1)
    fields.first.type.should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_selected_include_exact_origin?("SelectedBranchOwner", "initialize", "SelectedBranchInitializer").should be_true
    converter.__test_selected_include_exact_origin?("SelectedBranchOwner", "marker", "SelectedBranchInitializer").should be_true
  end

  it "runs macro included and retains its generated definition arena" do
    converter = selected_macro_class_include_fixture(<<-CRYSTAL)
      module SelectedBranchHook
        macro included
          def generated_marker : Int32
            70
          end
        end
      end
      class SelectedBranchOwner
        {% if true %}
          include SelectedBranchHook
        {% end %}
      end
    CRYSTAL
    converter.__test_selected_include_modules("SelectedBranchOwner").should eq(["SelectedBranchHook"])
    converter.__test_selected_include_registered_method?("SelectedBranchOwner", "generated_marker").should be_true
  end

  it "keeps a class declaration before the selected include ahead of the module" do
    converter = selected_macro_class_include_fixture(selected_macro_class_include_modules, <<-CRYSTAL)
      class SelectedBranchOwner
        def marker : Int32
          73
        end
        {% if true %}
          include SelectedBranchGood
        {% end %}
      end
    CRYSTAL
    converter.__test_selected_include_modules("SelectedBranchOwner").should eq(["SelectedBranchGood"])
    converter.__test_selected_include_exact_origin?("SelectedBranchOwner", "marker", "SelectedBranchGood").should be_false
    converter.__test_selected_include_registered_method?("SelectedBranchOwner", "marker").should be_true
  end

  it "keeps a class declaration after the selected include ahead of the module" do
    converter = selected_macro_class_include_fixture(selected_macro_class_include_modules, <<-CRYSTAL)
      class SelectedBranchOwner
        {% if true %}
          include SelectedBranchGood
        {% end %}
        def marker : Int32
          74
        end
      end
    CRYSTAL
    converter.__test_selected_include_modules("SelectedBranchOwner").should eq(["SelectedBranchGood"])
    converter.__test_selected_include_exact_origin?("SelectedBranchOwner", "marker", "SelectedBranchGood").should be_false
    converter.__test_selected_include_registered_method?("SelectedBranchOwner", "marker").should be_true
  end

  it "keeps the outer generic module binding on a generated Leaf include" do
    converter = selected_macro_class_include_fixture(<<-CRYSTAL)
      module SelectedFrameLeaf(T)
        def leaf_value(value : T) : T
          value
        end
      end
      module SelectedFrameOuter(T)
        macro included
          include SelectedFrameLeaf(T)
        end
      end
      class SelectedFrameOwner
        include SelectedFrameOuter(Int32)
      end
    CRYSTAL
    converter.__test_selected_include_binding("SelectedFrameOwner", "SelectedFrameOuter", "T").should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_selected_include_binding("SelectedFrameOwner", "SelectedFrameLeaf", "T").should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "restores independent generic include frames for distinct owners" do
    converter = selected_macro_class_include_fixture(<<-CRYSTAL)
      module SelectedFrameNamespace
        module Leaf(T)
          def leaf_value(value : T) : T
            value
          end
        end
      end
      module SelectedFrameOuter(T)
        macro included
          include SelectedFrameNamespace::Leaf(T)
        end
      end
      class SelectedFrameIntOwner
        {% if true %}
          include SelectedFrameOuter(Int32)
        {% end %}
      end
      class SelectedFrameBoolOwner
        {% if true %}
          include SelectedFrameOuter(Bool)
        {% end %}
      end
    CRYSTAL
    converter.__test_selected_include_binding("SelectedFrameIntOwner", "SelectedFrameOuter", "T").should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_selected_include_binding("SelectedFrameIntOwner", "SelectedFrameNamespace::Leaf", "T").should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_selected_include_binding("SelectedFrameBoolOwner", "SelectedFrameOuter", "T").should eq(Adamas::HIR::TypeRef::BOOL)
    converter.__test_selected_include_binding("SelectedFrameBoolOwner", "SelectedFrameNamespace::Leaf", "T").should eq(Adamas::HIR::TypeRef::BOOL)
  end
end
