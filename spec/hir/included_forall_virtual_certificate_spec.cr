require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_enable_certificate_lazy_module_methods : Nil
    @lazy_module_methods = true
  end
end

private def lower_virtual_certificate_fixture(lazy : Bool = false, unrelated_overload : Bool = false) : Adamas::HIR::AstToHir
  code = <<-CRYSTAL
    module CertificateFlow(Seed)
      def echo(value : T) : T forall T
        value
      end
    end

    class CertificateBase
      include CertificateFlow(UInt64)
    end

    class CertificateChild < CertificateBase
      def echo(value : Int32) : String
        "child"
      end
    end

    class CertificateDetached
      def echo(value : Int32) : String
        "detached"
      end
    end

    def certificate_route(value : CertificateBase)
      value.echo(42)
    end

    certificate_route(CertificateBase.new)
  CRYSTAL
  if unrelated_overload
    code += "\n"
    code += <<-CRYSTAL
      class CertificateOtherOverloadChild < CertificateBase
        def echo(value : String) : Int32
          99
        end
      end
    CRYSTAL
  end
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  converter.__test_enable_certificate_lazy_module_methods if lazy
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  defs = [] of Adamas::Compiler::Frontend::DefNode
  main = [] of UInt64
  result.roots.each do |id|
    case node = result.arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      modules << node
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::DefNode
      defs << node
    else
      main << id.index.to_u64
    end
  end
  modules.each { |node| converter.register_module(node) }
  classes.each { |node| converter.register_class(node) }
  defs.each { |node| converter.register_function(node) }
  unless lazy
    modules.each { |node| converter.lower_module(node) }
    classes.each { |node| converter.lower_class(node) }
    defs.each { |node| converter.lower_def(node) }
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter
end

describe "included-forall virtual return certificates" do
  it "preserves an inherited actual-argument target beside an unrelated direct overload" do
    converter = lower_virtual_certificate_fixture(lazy: true, unrelated_overload: true)
    converter.validate_included_forall_virtual_return_certificates!(converter.module)
    base = converter.module.functions.find { |function| function.name == "CertificateBase#echo$Int32" }.not_nil!
    child = converter.module.functions.find { |function| function.name == "CertificateChild#echo$Int32" }.not_nil!
    base.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    child.return_type.should eq(Adamas::HIR::TypeRef::STRING)
  end

  it "materializes exact targets during nested lazy call lowering" do
    converter = lower_virtual_certificate_fixture(lazy: true)
    converter.validate_included_forall_virtual_return_certificates!(converter.module)
    base = converter.module.functions.find { |function| function.name == "CertificateBase#echo$Int32" }.not_nil!
    child = converter.module.functions.find { |function| function.name == "CertificateChild#echo$Int32" }.not_nil!
    base.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    child.return_type.should eq(Adamas::HIR::TypeRef::STRING)
    base.blocks.any?(&.body_emitted).should be_true
    child.blocks.any?(&.body_emitted).should be_true
  end

  it "admits an unchanged union while concrete target returns remain exact" do
    converter = lower_virtual_certificate_fixture
    converter.validate_included_forall_virtual_return_certificates!(converter.module)
    base = converter.module.functions.find { |function| function.name == "CertificateBase#echo$Int32" }.not_nil!
    child = converter.module.functions.find { |function| function.name == "CertificateChild#echo$Int32" }.not_nil!
    base.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    child.return_type.should eq(Adamas::HIR::TypeRef::STRING)
    calls = converter.module.functions.flat_map(&.blocks).flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
    virtual = calls.find { |call| call.virtual && call.method_name == "CertificateBase#echo$Int32" }.not_nil!
    descriptor = converter.module.get_type_descriptor(virtual.type).not_nil!
    descriptor.kind.should eq(Adamas::HIR::TypeKind::Union)
    descriptor.name.split(" | ").sort.should eq(["Int32", "String"])
  end

  it "rejects a runtime descendant published after callsite return selection" do
    converter = lower_virtual_certificate_fixture
    converter.validate_included_forall_virtual_return_certificates!(converter.module)
    converter.module.register_class_parent("CertificateDetached", "CertificateBase")
    expect_raises(Adamas::HIR::LoweringError, /included-forall virtual target/) do
      converter.validate_included_forall_virtual_return_certificates!(converter.module)
    end
  end

  it "rejects a target return ABI changed after callsite return selection" do
    converter = lower_virtual_certificate_fixture
    converter.validate_included_forall_virtual_return_certificates!(converter.module)
    target = converter.module.functions.find { |function| function.name == "CertificateChild#echo$Int32" }.not_nil!
    target.return_type = Adamas::HIR::TypeRef::INT64
    expect_raises(Adamas::HIR::LoweringError, /included-forall virtual target/) do
      converter.validate_included_forall_virtual_return_certificates!(converter.module)
    end
  end

  it "rejects a selected forall body whose static return differs from its actual binding" do
    converter = lower_virtual_certificate_fixture
    converter.validate_included_forall_virtual_return_certificates!(converter.module)
    target = converter.module.functions.find { |function| function.name == "CertificateBase#echo$Int32" }.not_nil!
    target.return_type = Adamas::HIR::TypeRef::INT64
    expect_raises(Adamas::HIR::LoweringError, /included-forall virtual target/) do
      converter.validate_included_forall_virtual_return_certificates!(converter.module)
    end
  end
end
