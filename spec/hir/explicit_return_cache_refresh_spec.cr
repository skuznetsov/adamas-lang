require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_explicit_return_refresh(name : String, base_name : String = name) : Adamas::HIR::TypeRef?
    resolve_return_type_from_def(name, base_name, nil, selected_def: @function_defs[name])
  end

  def __test_explicit_return_seed_contract(
    name : String,
    node : Adamas::Compiler::Frontend::DefNode,
    type : Adamas::HIR::TypeRef,
  ) : Nil
    set_function_def_entry(name, node)
    record_explicit_return_contract(name, node, true, type)
    set_function_type_entry(name, type, allow_explicit_replacement: true)
    set_function_base_return_type(name, type) if strip_type_suffix(name) == name
  end

  def __test_explicit_return_resolve_selected(
    name : String,
    base_name : String,
    node : Adamas::Compiler::Frontend::DefNode,
    bindings : Hash(String, String) = {} of String => String,
  ) : Adamas::HIR::TypeRef?
    with_type_param_map(bindings) do
      resolve_return_type_from_def(name, base_name, nil, selected_def: node)
    end
  end

  def __test_explicit_return_registered_def(name : String) : Adamas::Compiler::Frontend::DefNode
    @function_defs[name]
  end

  def __test_explicit_return_cached_type(name : String) : Adamas::HIR::TypeRef?
    @function_types[name]?
  end

  def __test_explicit_return_cached_base_type(name : String) : Adamas::HIR::TypeRef?
    @function_base_return_types[name]?
  end

  def __test_explicit_return_refresh_type_name(type : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type)
  end
end

private def explicit_return_refresh_program(code : String)
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code),
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  {converter, result}
end

describe "explicit return cache refresh" do
  it "publishes a newly resolved nested return type to the declaration cache" do
    converter, result = explicit_return_refresh_program(<<-CRYSTAL)
      module RefreshOwner
        class Context
          def allocate : Stack
            Stack.new
          end
        end
      end
      module RefreshOwner
        struct Stack
        end
      end
    CRYSTAL
    converter.register_module(result.arena[result.roots[0]].as(Adamas::Compiler::Frontend::ModuleNode))
    name = "RefreshOwner::Context#allocate"
    before = converter.__test_explicit_return_cached_type(name).not_nil!
    converter.register_module(result.arena[result.roots[1]].as(Adamas::Compiler::Frontend::ModuleNode))

    resolved = converter.__test_explicit_return_refresh(name).not_nil!
    converter.__test_explicit_return_refresh_type_name(resolved).should eq("RefreshOwner::Stack")
    resolved.should_not eq(before)
    converter.__test_explicit_return_cached_type(name).should eq(resolved)
    converter.__test_explicit_return_cached_base_type(name).should eq(resolved)
  end

  it "refreshes matching aliases without replacing a sibling overload's base cache" do
    converter, result = explicit_return_refresh_program(<<-CRYSTAL)
      module RefreshSibling
        class Context
          def allocate : Stack
            Stack.new
          end
          def unrelated : String
            "sibling"
          end
        end
      end
      module RefreshSibling
        struct Stack
        end
      end
    CRYSTAL
    converter.register_module(result.arena[result.roots[0]].as(Adamas::Compiler::Frontend::ModuleNode))
    base = "RefreshSibling::Context#allocate"
    mangled = "#{base}$Int32"
    selected = converter.__test_explicit_return_registered_def(base)
    sibling = converter.__test_explicit_return_registered_def("RefreshSibling::Context#unrelated")
    before = converter.__test_explicit_return_cached_type(base).not_nil!
    converter.__test_explicit_return_seed_contract(mangled, selected, before)
    converter.__test_explicit_return_seed_contract(base, sibling, Adamas::HIR::TypeRef::STRING)
    converter.register_module(result.arena[result.roots[1]].as(Adamas::Compiler::Frontend::ModuleNode))

    resolved = converter.__test_explicit_return_resolve_selected(mangled, base, selected).not_nil!
    converter.__test_explicit_return_refresh_type_name(resolved).should eq("RefreshSibling::Stack")
    converter.__test_explicit_return_cached_type(mangled).should eq(resolved)
    converter.__test_explicit_return_cached_type(base).should eq(Adamas::HIR::TypeRef::STRING)
    converter.__test_explicit_return_cached_base_type(base).should eq(Adamas::HIR::TypeRef::STRING)
  end

  it "does not publish a contextual type parameter into another specialization's cache" do
    converter, result = explicit_return_refresh_program(<<-CRYSTAL)
      def generic_value : T
        0
      end
    CRYSTAL
    node = result.arena[result.roots.first].as(Adamas::Compiler::Frontend::DefNode)
    name = "RefreshGeneric#value$Int32"
    base = "RefreshGeneric#value"
    converter.__test_explicit_return_seed_contract(name, node, Adamas::HIR::TypeRef::INT32)
    converter.__test_explicit_return_seed_contract(base, node, Adamas::HIR::TypeRef::INT32)

    resolved = converter.__test_explicit_return_resolve_selected(name, base, node, {"T" => "String"})
    resolved.should eq(Adamas::HIR::TypeRef::STRING)
    converter.__test_explicit_return_cached_type(name).should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_explicit_return_cached_type(base).should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_explicit_return_cached_base_type(base).should eq(Adamas::HIR::TypeRef::INT32)
  end
end
