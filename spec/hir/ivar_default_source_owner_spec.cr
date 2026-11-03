require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def ivar_default_source_owner_fixture(module_source : String, class_source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(module_source))
  module_program = parser.parse_program
  parser.diagnostics.should be_empty
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(class_source))
  class_program = parser.parse_program
  parser.diagnostics.should be_empty
  module_arena = module_program.arena
  class_arena = class_program.arena
  converter = Adamas::HIR::AstToHir.new(class_arena, sources_by_arena: {
    module_arena.object_id.to_u64 => module_source,
    class_arena.object_id.to_u64 => class_source,
  })
  converter.no_prelude = true
  converter.arena = module_arena
  modules = module_program.roots.map { |root| module_arena[root].as(Adamas::Compiler::Frontend::ModuleNode) }
  modules.each { |node| converter.register_module(node) }
  modules.each { |node| converter.lower_module(node) }
  converter.arena = class_arena
  classes = class_program.roots.map { |root| class_arena[root].as(Adamas::Compiler::Frontend::ClassNode) }
  classes.each { |node| converter.register_class(node) }
  classes.each { |node| converter.lower_class(node) }
  {converter, module_arena, class_arena}
end

describe "ivar default declaration ownership" do
  it "keeps a module initializer's source arena and lexical owner after inclusion and alignment" do
    converter, module_arena, _ = ivar_default_source_owner_fixture(<<-CRYSTAL, <<-CRYSTAL)
      module IvarDefaultOwner
        CODE = 65
        @code : Int32 = CODE
      end
      CRYSTAL
      class IvarDefaultConsumer
        CODE = 66
        include IvarDefaultOwner
      end
      CRYSTAL
    field = converter.class_info["IvarDefaultConsumer"].ivars.find(&.name.==("@code")).not_nil!
    source = field.default_source.not_nil!
    source.lexical_owner.should eq("IvarDefaultOwner")
    source.execution_scope.should eq(Adamas::HIR::IVarDefaultScope::TypeBody)
    source.arena.object_id.should eq(module_arena.object_id)
    field.default_expr_id.should eq(source.expr_id)
    field.default_arena.should eq(source.arena)
  end

  it "preserves the same declaration receipt when a subclass copies its parent's layout" do
    converter, module_arena, _ = ivar_default_source_owner_fixture(<<-CRYSTAL, <<-CRYSTAL)
      module IvarInheritedOwner
        CODE = 65
        @code : Int32? = CODE
      end
      CRYSTAL
      class IvarDefaultParent
        include IvarInheritedOwner
      end
      class IvarDefaultChild < IvarDefaultParent
        CODE = 66
      end
      CRYSTAL
    parent = converter.class_info["IvarDefaultParent"].ivars.find(&.name.==("@code")).not_nil!
    child = converter.class_info["IvarDefaultChild"].ivars.find(&.name.==("@code")).not_nil!
    child.default_source.should eq(parent.default_source)
    child.default_source.not_nil!.lexical_owner.should eq("IvarInheritedOwner")
    child.default_arena.not_nil!.object_id.should eq(module_arena.object_id)
  end

  it "retains applied module type bindings with the initializer source" do
    converter, _, _ = ivar_default_source_owner_fixture(<<-CRYSTAL, <<-CRYSTAL)
      module IvarGenericOwner(T)
        @code : T = uninitialized T
      end
      CRYSTAL
      class IvarGenericConsumer
        include IvarGenericOwner(Int32)
      end
      CRYSTAL
    field = converter.class_info["IvarGenericConsumer"].ivars.find(&.name.==("@code")).not_nil!
    source = field.default_source.not_nil!
    source.lexical_owner.should eq("IvarGenericOwner(T)")
    source.type_bindings["T"].lstrip(':').should eq("Int32")
  end
end
