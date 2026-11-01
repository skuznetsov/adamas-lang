require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_concrete_type_args(args : Array(String), bindings : Hash(String, String)) : Bool
    with_isolated_type_param_map(bindings) do
      concrete_type_args?(args)
    end
  end

  def __test_concrete_generic_type_name(name : String, bindings : Hash(String, String)) : Bool
    with_isolated_type_param_map(bindings) do
      if application = split_generic_base_and_args(name)
        concrete_type_args?(split_generic_type_args(application.args))
      else
        false
      end
    end
  end

  def __test_concrete_type_args_in_owner(args : Array(String), owner : String) : Bool
    old_class = @current_class
    old_map = @type_param_map
    begin
      @current_class = owner
      @type_param_map = {} of String => String
      concrete_type_args?(args)
    ensure
      @current_class = old_class
      @type_param_map = old_map
    end
  end

  def __test_direct_readiness_map_mutations : {Bool, Bool, Bool, Bool, Bool}
    old_class = @current_class
    old_map = @type_param_map
    begin
      @current_class = "Box(T)"
      bindings = {"T" => "T"}
      @type_param_map = bindings

      self_binding = unresolved_generic_type_arg?("T")
      bindings["T"] = "Int32"
      concrete_binding = unresolved_generic_type_arg?("T")
      bindings.delete("T")
      unbound_formal = unresolved_generic_type_arg?("T")
      @unresolved_generic_arg_cache.clear
      uncached_unbound_formal = unresolved_generic_type_arg?("T")
      bindings["T"] = "T"
      restored_self_binding = unresolved_generic_type_arg?("T")
      {
        self_binding,
        concrete_binding,
        unbound_formal,
        uncached_unbound_formal,
        restored_self_binding,
      }
    ensure
      @current_class = old_class
      @type_param_map = old_map
    end
  end

  def __test_register_source_class(node : Adamas::Compiler::Frontend::ClassNode, arena : Adamas::Compiler::Frontend::ArenaLike) : Nil
    old_arena = @arena
    begin
      @arena = arena
      register_class(node)
    ensure
      @arena = old_arena
    end
  end

  def __test_register_readiness_alias(name : String, target : String) : Nil
    register_type_alias(name, target)
  end

  def __test_result_type_unresolved(name : String) : Bool
    unresolved_generic_return_type?(type_ref_for_name(name))
  end

end

private def registered_type_identity_converter
  source = <<-CRYSTAL
    class F
    end
    class E
    end
    class Box(T)
    end
    class T
    end
    class Array(A)
    end
    class StaticArray(A, N)
    end
    module Foo
      class T
      end
    end
    N = 4
    TEXT_VALUE = "not a type"
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/registered_type_identity.cr"})
  converter.no_prelude = true
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::ConstantNode
      converter.register_constant(node)
    end
  end
  converter
end

describe "registered generic argument readiness" do
  it "rejects an arbitrary generic formal carried through another formal binding" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    program = parser.parse_program
    converter = Adamas::HIR::AstToHir.new(program.arena)
    converter.no_prelude = true
    converter.__test_concrete_type_args(["F"], {"T" => "F"}).should be_false
  end

  it "uses registered source identity for short and qualified nominal names" do
    converter = registered_type_identity_converter
    converter.__test_concrete_type_args(["F"], {} of String => String).should be_true
    converter.__test_concrete_type_args(["T"], {} of String => String).should be_true
    converter.__test_concrete_type_args(["Foo::T"], {} of String => String).should be_true
    converter.__test_concrete_type_args(["T"], {"T" => "Foo::T"}).should be_true
    converter.__test_concrete_type_args(["Array(Int32)"], {} of String => String).should be_true
  end

  it "keeps an active self-bound formal unresolved even when a matching class exists" do
    converter = registered_type_identity_converter
    converter.__test_concrete_type_args(["F"], {"F" => "F"}).should be_false
    converter.__test_concrete_type_args(["E"], {"E" => "E"}).should be_false
    converter.__test_concrete_type_args(["Array(E)"], {"E" => "E"}).should be_false
    converter.__test_concrete_type_args(["Tuple(E, Int32)"], {"E" => "E"}).should be_false
    converter.__test_concrete_type_args(["F"], {"F" => "::F"}).should be_true
  end

  it "keeps an unbound enclosing formal unresolved despite a same-named class" do
    converter = registered_type_identity_converter
    converter.__test_concrete_type_args_in_owner(["T"], "Box(T)").should be_false
  end

  it "keys readiness by direct type-map contents and restores prior answers" do
    converter = registered_type_identity_converter
    converter.__test_direct_readiness_map_mutations.should eq({true, false, true, true, true})
  end

  it "refreshes unresolved admission after a source nominal is registered" do
    empty_source = ""
    empty_parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(empty_source))
    empty_program = empty_parser.parse_program
    empty_arena = empty_program.arena
    converter = Adamas::HIR::AstToHir.new(empty_arena,
      sources_by_arena: {empty_arena.object_id.to_u64 => empty_source})
    converter.no_prelude = true
    converter.__test_concrete_type_args(["F"], {} of String => String).should be_false

    source = "class F\nend\n"
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    node = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
    converter.__test_register_source_class(node, program.arena)
    converter.__test_concrete_type_args(["F"], {} of String => String).should be_true
  end

  it "admits a registered numeric constant in StaticArray arity" do
    converter = registered_type_identity_converter
    converter.__test_concrete_type_args(["UInt8", "N"], {} of String => String).should be_true
    converter.__test_concrete_generic_type_name("StaticArray(UInt8, N)", {} of String => String).should be_true
  end

  it "preserves explicit non-concrete generic argument exclusions" do
    converter = registered_type_identity_converter
    ["NoReturn", "Array", "typeof(1)"].each do |argument|
      converter.__test_concrete_type_args([argument], {} of String => String).should be_false
    end
  end

  it "does not treat a self-cyclic alias or a non-type constant as a type identity" do
    converter = registered_type_identity_converter
    converter.__test_register_readiness_alias("ReadinessAliasCycle", "ReadinessAliasCycle")
    converter.__test_concrete_type_args(["ReadinessAliasCycle"], {} of String => String).should be_false
    converter.__test_register_readiness_alias("ReadinessCycleA", "ReadinessCycleB")
    converter.__test_register_readiness_alias("ReadinessCycleB", "ReadinessCycleA")
    converter.__test_concrete_type_args(["ReadinessCycleA"], {} of String => String).should be_false
    11.times do |index|
      converter.__test_register_readiness_alias("ReadinessLongCycle#{index}", "ReadinessLongCycle#{(index + 1) % 11}")
    end
    converter.__test_concrete_type_args(["ReadinessLongCycle0"], {} of String => String).should be_false
    converter.__test_concrete_type_args(["TEXT_VALUE"], {} of String => String).should be_false
  end

  it "accepts an absolute path to a registered nested nominal type" do
    converter = registered_type_identity_converter
    converter.__test_register_readiness_alias("AbsoluteF", "F")
    converter.__test_concrete_type_args(["::Foo::T"], {} of String => String).should be_true
    converter.__test_concrete_type_args(["::Foo::T"], {"T" => "T"}).should be_true
    converter.__test_concrete_type_args(["::F"], {"F" => "F"}).should be_true
    converter.__test_concrete_type_args(["::AbsoluteF"], {"F" => "F"}).should be_true
    converter.__test_concrete_type_args(["::UInt64"], {} of String => String).should be_true
    converter.__test_concrete_type_args(["::Pointer(::UInt8)"], {} of String => String).should be_true

  end

  it "does not overreject registered and compiler-special result types" do
    converter = registered_type_identity_converter
    {"Int32", "UInt8", "String", "Nil", "Void", "NoReturn", "Pointer(Void)",
     "Proc(Int32, Void)", "Tuple()", "StaticArray(UInt8, 4)"}.each do |name|
      converter.__test_result_type_unresolved(name).should be_false, name
    end
  end
end
