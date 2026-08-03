require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/mir/hir_to_mir"

private HEADER_PROC_GENERIC_STRUCT_UNION_SOURCE = <<-CRYSTAL
  struct DispatchHandler
    getter tag : Int32

    def initialize(@tag : Int32)
    end
  end

  struct DispatchBox(T)
    getter payload : T

    def initialize(@payload : T)
    end
  end

  def dispatched_payload(value : DispatchBox(DispatchHandler) | DispatchBox(Proc(Int32, Nil)))
    value.payload
  end

  dispatched_payload(DispatchBox(DispatchHandler).new(DispatchHandler.new(7)))
CRYSTAL

private def lower_header_proc_generic_struct_union_source : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(HEADER_PROC_GENERIC_STRUCT_UNION_SOURCE)
  )
  program = parser.parse_program
  raise "parser diagnostics: #{parser.diagnostics.size}" unless parser.diagnostics.empty?

  arena = program.arena
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  definitions = [] of Adamas::Compiler::Frontend::DefNode
  main_exprs = [] of UInt64

  program.roots.each do |expr_id|
    case node = arena[expr_id]
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::DefNode
      definitions << node
    when Adamas::Compiler::Frontend::CallNode
      main_exprs << expr_id.index.to_u64
    end
  end

  converter = Adamas::HIR::AstToHir.new(arena)
  classes.each { |node| converter.register_class(node) }
  definitions.each { |node| converter.register_function(node) }
  classes.each { |node| converter.lower_class(node) }
  definitions.each { |node| converter.lower_def(node) }
  converter.lower_main(main_exprs)
  converter.flush_pending_functions
  converter
end

describe "header/Proc generic struct union return ABI" do
  it "preserves concrete branch calls and exact wraps through MIR lowering" do
    converter = lower_header_proc_generic_struct_union_source
    hir_caller = converter.module.functions.find do |function|
      function.name.starts_with?("dispatched_payload$")
    end
    hir_caller.should_not be_nil

    lowering = Adamas::MIR::HIRToMIRLowering.new(converter.module)
    lowering.register_union_types(converter.union_descriptor_entries)
    lowering.register_class_types(converter.class_info)
    mir_module = lowering.lower

    caller = mir_module.functions.find { |function| function.name == hir_caller.not_nil!.name }
    caller.should_not be_nil
    caller = caller.not_nil!

    instructions = caller.blocks.flat_map(&.instructions)
    payload_calls = instructions.compact_map(&.as?(Adamas::MIR::Call)).select do |call|
      callee = mir_module.functions.find { |function| function.id == call.callee }
      callee.try(&.name.ends_with?("#payload")) || false
    end
    payload_calls.size.should eq(2)
    payload_calls.map(&.type).uniq.size.should eq(2)
    payload_calls.none? { |call| call.type == caller.return_type }.should be_true

    union_descriptor = mir_module.get_union_descriptor(caller.return_type)
    union_descriptor.should_not be_nil
    union_descriptor = union_descriptor.not_nil!
    wraps = instructions.compact_map(&.as?(Adamas::MIR::UnionWrap))
    wraps_by_value = wraps.to_h { |wrap| {wrap.value, wrap} }
    wrapped_variant_ids = [] of Int32
    canonical_proc_bridges = 0

    payload_calls.each do |call|
      callee = mir_module.functions.find { |function| function.id == call.callee }
      callee.should_not be_nil
      callee.not_nil!.return_type.should eq(call.type)

      wrap = wraps_by_value[call.id]?
      wrap.should_not be_nil
      wrap = wrap.not_nil!
      wrap.type.should eq(caller.return_type)
      wrap.union_type.should eq(caller.return_type)

      variant = union_descriptor.variants.find do |candidate|
        candidate.type_id == wrap.variant_type_id
      end
      variant.should_not be_nil
      variant = variant.not_nil!
      wrapped_variant_ids << variant.type_id

      next if variant.type_ref == call.type

      variant.full_name.should eq("Proc")
      callee.not_nil!.name.should contain("DispatchBox(Proc(")
      canonical_proc_bridges += 1
    end
    wrapped_variant_ids.uniq.size.should eq(2)
    canonical_proc_bridges.should eq(1)

    result_phi = instructions.compact_map(&.as?(Adamas::MIR::Phi)).find do |phi|
      phi.type == caller.return_type
    end
    result_phi.should_not be_nil
    result_phi.not_nil!.incoming.each do |(_, value_id)|
      wraps.any? { |wrap| wrap.id == value_id }.should be_true
    end
  end
end
