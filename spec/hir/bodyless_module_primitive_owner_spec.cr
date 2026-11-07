require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def spec_force_module_primitive(name : String, types : Array(TypeRef), depth : Int32 = 0)
    remember_callsite_arg_types(name, types)
    saved = @force_lower_return_type_depth
    @force_lower_return_type_depth = depth
    begin
      force_lower_function_for_return_type(name)
    ensure
      @force_lower_return_type_depth = saved
    end
    @force_lower_depth_refused.includes?(name)
  end
end

private def module_primitive_converter(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |id|
    if node = arena[id].as?(Adamas::Compiler::Frontend::ModuleNode)
      converter.register_module(node)
    end
  end
  converter
end

describe "bodyless module primitive source ownership" do
  it "does not lower a registered primitive as an empty Nil-returning body" do
    converter = module_primitive_converter(<<-CRYSTAL)
      module PrimitiveOwner
        @[Primitive(:load_atomic)]
        def self.read(value : Bool) : Bool
        end
      end
      CRYSTAL
    name = "PrimitiveOwner.read$Bool"
    converter.spec_force_module_primitive(name, [Adamas::HIR::TypeRef::BOOL]).should be_false
    converter.module.has_function_with_body?(name).should be_false
  end

  it "does not record a body-demand depth refusal for a primitive" do
    converter = module_primitive_converter(<<-CRYSTAL)
      module PrimitiveOwner
        @[Primitive(:load_atomic)]
        def self.read(value : Bool) : Bool
        end
      end
      CRYSTAL
    converter.spec_force_module_primitive("PrimitiveOwner.read$Bool", [Adamas::HIR::TypeRef::BOOL], 4).should be_false
  end

  it "still validates an ordinary empty method" do
    converter = module_primitive_converter(<<-CRYSTAL)
      module OrdinaryOwner
        def self.read(value : Bool) : Bool
        end
      end
      CRYSTAL
    expect_raises(Adamas::HIR::LoweringError, /must return Bool.*returning Nil/) do
      converter.spec_force_module_primitive("OrdinaryOwner.read$Bool", [Adamas::HIR::TypeRef::BOOL])
    end
  end

  it "does not give a primitive sibling authority over an ordinary overload" do
    converter = module_primitive_converter(<<-CRYSTAL)
      module OverloadedOwner
        @[Primitive(:load_atomic)]
        def self.read(value : Int32) : Bool
        end
        def self.read(value : Bool) : Bool
        end
      end
      CRYSTAL
    expect_raises(Adamas::HIR::LoweringError, /must return Bool.*returning Nil/) do
      converter.spec_force_module_primitive("OverloadedOwner.read$Bool", [Adamas::HIR::TypeRef::BOOL])
    end
  end
end
