require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/mir/hir_to_mir"

describe "generic module receiver registration" do
  it "registers a concrete module application as a runtime reference view" do
    hir = Adamas::HIR::Module.new("generic_module_reference")
    receiver = hir.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Generic, "ReferenceView(Int32)", [Adamas::HIR::TypeRef::INT32]))
    hir.register_module_includer("ReferenceView", "ConcreteCarrier")
    lowering = Adamas::MIR::HIRToMIRLowering.new(hir)
    lowering.register_module_types(hir.types)
    mir_type = lowering.mir_module.type_registry.get(Adamas::MIR::TypeRef.from_hir(receiver))
    mir_type.should_not be_nil
    Adamas::MIR.runtime_header_backed_type?(mir_type).should be_true
  end

  it "does not infer module identity from a short-name collision" do
    hir = Adamas::HIR::Module.new("generic_module_reference")
    receiver = hir.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Generic, "ValueOwner::ReferenceView(Int32)", [Adamas::HIR::TypeRef::INT32]))
    hir.register_module_includer("OtherOwner::ReferenceView", "ConcreteCarrier")
    lowering = Adamas::MIR::HIRToMIRLowering.new(hir)
    lowering.register_module_types(hir.types)
    mir_type = lowering.mir_module.type_registry.get(Adamas::MIR::TypeRef.from_hir(receiver))
    Adamas::MIR.runtime_header_backed_type?(mir_type).should be_false
  end

  it "recognizes a qualified applied module key without a bare-key alias" do
    hir = Adamas::HIR::Module.new("generic_module_reference")
    receiver = hir.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Generic, "ViewOwner::ReferenceView(Int32)", [Adamas::HIR::TypeRef::INT32]))
    hir.register_module_includer("ViewOwner::ReferenceView(Int32)", "ConcreteCarrier")
    lowering = Adamas::MIR::HIRToMIRLowering.new(hir)
    lowering.register_module_types(hir.types)
    mir_type = lowering.mir_module.type_registry.get(Adamas::MIR::TypeRef.from_hir(receiver))
    Adamas::MIR.runtime_header_backed_type?(mir_type).should be_true
  end

  it "leaves unrelated generic value and pointer descriptors unregistered" do
    hir = Adamas::HIR::Module.new("generic_module_reference")
    values = ["ValueBox(Int32)", "Pointer(Int32)", "Slice(Int32)"].map do |name|
      hir.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Generic, name, [Adamas::HIR::TypeRef::INT32]))
    end
    lowering = Adamas::MIR::HIRToMIRLowering.new(hir)
    lowering.register_module_types(hir.types)
    values.each do |value|
      mir_type = lowering.mir_module.type_registry.get(Adamas::MIR::TypeRef.from_hir(value))
      Adamas::MIR.runtime_header_backed_type?(mir_type).should be_false
    end
  end
end
