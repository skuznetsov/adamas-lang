require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/hir/escape_analysis"
require "../../src/compiler/hir/taint_analysis"
require "../../src/compiler/hir/memory_strategy"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"

class Adamas::MIR::HIRToMIRLowering
  def __test_resolve_virtual_method_for_class(
    class_name : String,
    method_suffix : String,
    arg_count : Int32,
    allow_module_method : Bool = false,
  ) : Adamas::MIR::Function?
    resolve_virtual_method_for_class(class_name, method_suffix, arg_count, allow_module_method)
  end

  def __test_virtual_dispatch_candidate_type_ids(
    recv_desc : Adamas::HIR::TypeDescriptor,
    recv_type : Adamas::HIR::TypeRef,
    method_suffix : String,
    arg_count : Int32,
  ) : Array(Int32)
    virtual_dispatch_candidates(recv_desc, recv_type, method_suffix, arg_count).map(&.type_id)
  end

  def __test_synthesize_class_dispatch_for_abstract(
    class_name : String,
    method_suffix : String,
    candidates : Array(Tuple(String, Adamas::MIR::Function)),
  ) : Adamas::MIR::Function?
    synthesize_class_dispatch_for_abstract(class_name, method_suffix, candidates)
  end

  def __test_lower_virtual_dispatch_for_receiver(
    recv_type : Adamas::HIR::TypeRef,
    call : Adamas::HIR::Call,
  ) : Adamas::MIR::ValueId?
    @hir_value_types[call.receiver_value] = recv_type
    test_func = @mir_module.create_function(
      "__test_lower_virtual_dispatch",
      Adamas::MIR::TypeRef.from_hir(call.type)
    )
    test_func.add_param("recv", Adamas::MIR::TypeRef.from_hir(recv_type))
    @builder = Adamas::MIR::Builder.new(test_func)
    lower_virtual_dispatch(call, [0_u32])
  end

  def __test_ensure_class_dispatch_for_union(
    class_name : String,
    receiver_type : Adamas::MIR::TypeRef,
    call : Adamas::HIR::Call,
  ) : Adamas::MIR::Function?
    ensure_class_dispatch_for_union(class_name, "probe", receiver_type, call)
  end

  def __test_proc_callback_return_hir_type(
    block_type : Adamas::HIR::TypeRef,
  ) : Adamas::HIR::TypeRef?
    proc_callback_return_hir_type(block_type)
  end

  def __test_heap_proc_indirect_calls : Array(Adamas::MIR::IndirectCall)
    func = @mir_module.create_function("__test_heap_proc_dispatch", Adamas::MIR::TypeRef::INT32)
    func.add_param("proc", Adamas::MIR::TypeRef::POINTER)
    func.add_param("value", Adamas::MIR::TypeRef::INT32)
    @builder = Adamas::MIR::Builder.new(func)
    call_heap_proc(0_u32, [1_u32], Adamas::MIR::TypeRef::INT32)
    func.blocks.flat_map(&.instructions).select(&.is_a?(Adamas::MIR::IndirectCall)).map(&.as(Adamas::MIR::IndirectCall))
  end
end

describe Adamas::MIR::HIRToMIRLowering do
  describe "static method family resolution" do
    it "fails closed instead of choosing an overload by insertion order" do
      outcomes = [
        ["IdentityProbe#pick$Int32", "IdentityProbe#pick$String"],
        ["IdentityProbe#pick$String", "IdentityProbe#pick$Int32"],
      ].map do |target_order|
        hir_mod = Adamas::HIR::Module.new("ambiguous_static_method_family")

        target_order.each_with_index do |target_name, index|
          target = hir_mod.create_function(target_name, Adamas::HIR::TypeRef::INT32)
          target_block = target.get_block(target.entry_block)
          value = Adamas::HIR::Literal.new(
            target.next_value_id,
            Adamas::HIR::TypeRef::INT32,
            index.to_i64
          )
          target_block.add(value)
          target_block.terminator = Adamas::HIR::Return.new(value.id)
        end

        caller = hir_mod.create_function("identity_probe_caller", Adamas::HIR::TypeRef::INT32)
        caller_block = caller.get_block(caller.entry_block)
        call = Adamas::HIR::Call.without_receiver(
          caller.next_value_id,
          Adamas::HIR::TypeRef::INT32,
          "IdentityProbe#pick$Bool",
          [] of Adamas::HIR::ValueId
        )
        caller_block.add(call)
        caller_block.terminator = Adamas::HIR::Return.new(call.id)

        begin
          mir_mod = Adamas::MIR::HIRToMIRLowering.new(hir_mod).lower
          mir_caller = mir_mod.functions.find { |function| function.name == caller.name }.not_nil!
          mir_call = mir_caller.blocks
            .flat_map(&.instructions)
            .find(&.is_a?(Adamas::MIR::Call))
            .not_nil!
            .as(Adamas::MIR::Call)
          callee = mir_mod.functions.find { |function| function.id == mir_call.callee }.not_nil!
          "resolved: #{callee.name}"
        rescue ex
          ex.message || ex.class.name
        end
      end

      outcomes.should eq([
        "Ambiguous MIR call target IdentityProbe#pick$Bool: candidates IdentityProbe#pick$Int32, IdentityProbe#pick$String",
        "Ambiguous MIR call target IdentityProbe#pick$Bool: candidates IdentityProbe#pick$Int32, IdentityProbe#pick$String",
      ])
    end

    it "preserves the backend-owned stdio constructor target" do
      hir_mod = Adamas::HIR::Module.new("backend_owned_stdio_constructor")

      ["IO::FileDescriptor.new", "IO::FileDescriptor.new$Int32_Bool_Bool"].each do |target_name|
        target = hir_mod.create_function(target_name, Adamas::HIR::TypeRef::POINTER)
        target.add_param("handle", Adamas::HIR::TypeRef::INT32)
        target.add_param("close_on_finalize", Adamas::HIR::TypeRef::BOOL)
        target.set_param_default_literal(1, "true")
        target.add_param("blocking", Adamas::HIR::TypeRef::NIL)
        target.set_param_default_literal(2, "nil")
        target_block = target.get_block(target.entry_block)
        value = Adamas::HIR::Literal.new(
          target.next_value_id,
          Adamas::HIR::TypeRef::POINTER,
          nil
        )
        target_block.add(value)
        target_block.terminator = Adamas::HIR::Return.new(value.id)
      end

      caller = hir_mod.create_function("stdio_constructor_caller", Adamas::HIR::TypeRef::POINTER)
      caller_block = caller.get_block(caller.entry_block)
      handle = Adamas::HIR::Literal.new(
        caller.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        1_i64
      )
      caller_block.add(handle)
      call = Adamas::HIR::Call.without_receiver(
        caller.next_value_id,
        Adamas::HIR::TypeRef::POINTER,
        "IO::FileDescriptor.new$Int32",
        [handle.id]
      )
      caller_block.add(call)
      caller_block.terminator = Adamas::HIR::Return.new(call.id)

      mir_mod = Adamas::MIR::HIRToMIRLowering.new(hir_mod).lower
      mir_caller = mir_mod.functions.find { |function| function.name == caller.name }.not_nil!
      extern_call = mir_caller.blocks
        .flat_map(&.instructions)
        .find(&.is_a?(Adamas::MIR::ExternCall))
        .not_nil!
        .as(Adamas::MIR::ExternCall)

      extern_call.extern_name.should eq("IO::FileDescriptor.new$Int32")
      mir_caller.blocks
        .flat_map(&.instructions)
        .any?(&.is_a?(Adamas::MIR::Call))
        .should be_false
    end
  end

  describe "materialized Proc yield ABI" do
    it "recovers the concrete callback return from a Nil|Proc union" do
      hir_mod = Adamas::HIR::Module.new("proc_yield_callback_return")
      proc_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Proc,
        "Proc",
        [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32]
      ))
      block_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Union,
        "Nil | Proc(Int32, Int32)"
      ))
      result_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Union,
        "Nil | Int32"
      ))

      block_mir_ref = Adamas::MIR::TypeRef.from_hir(block_ref)
      proc_mir_ref = Adamas::MIR::TypeRef.from_hir(proc_ref)
      descriptor = Adamas::MIR::UnionDescriptor.new(
        "Nil | Proc(Int32, Int32)",
        [
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 1,
            type_ref: proc_mir_ref,
            full_name: "Proc(Int32, Int32)",
            size: 8,
            alignment: 8,
            field_offsets: nil
          ),
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 0,
            type_ref: Adamas::MIR::TypeRef::NIL,
            full_name: "Nil",
            size: 0,
            alignment: 1,
            field_offsets: nil
          ),
        ],
        16,
        8
      )

      result_mir_ref = Adamas::MIR::TypeRef.from_hir(result_ref)
      result_descriptor = Adamas::MIR::UnionDescriptor.new(
        "Nil | Int32",
        [
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: Adamas::MIR::TypeRef::INT32.id.to_i32,
            type_ref: Adamas::MIR::TypeRef::INT32,
            full_name: "Int32",
            size: 4,
            alignment: 4,
            field_offsets: nil
          ),
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 0,
            type_ref: Adamas::MIR::TypeRef::NIL,
            full_name: "Nil",
            size: 0,
            alignment: 1,
            field_offsets: nil
          ),
        ],
        16,
        8
      )

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.register_union_types([
        Adamas::HIR::UnionDescriptorRegistration.new(block_mir_ref, descriptor),
        Adamas::HIR::UnionDescriptorRegistration.new(result_mir_ref, result_descriptor),
      ])

      lowering.__test_proc_callback_return_hir_type(block_ref).should eq(Adamas::HIR::TypeRef::INT32)
    end

    it "fails closed when a block union has Proc variants with different returns" do
      hir_mod = Adamas::HIR::Module.new("ambiguous_proc_yield_callback_return")
      proc_i32_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Proc,
        "Proc",
        [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32]
      ))
      proc_i64_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Proc,
        "Proc",
        [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT64]
      ))
      block_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Union,
        "Nil | Proc(Int32, Int32) | Proc(Int32, Int64)"
      ))
      result_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Union,
        "Nil | Int32"
      ))
      func = hir_mod.create_function("invoke$ambiguous_block", result_ref)
      block_param = func.add_param("block", block_ref, true)
      func_block = func.get_block(func.entry_block)
      arg = Adamas::HIR::Literal.new(func.next_value_id, Adamas::HIR::TypeRef::INT32, 1_i64)
      func_block.add(arg)
      yld = Adamas::HIR::Yield.new(func.next_value_id, result_ref, [arg.id], block_param.id)
      func_block.add(yld)
      func_block.terminator = Adamas::HIR::Return.new(yld.id)
      descriptor = Adamas::MIR::UnionDescriptor.new(
        "Nil | Proc(Int32, Int32) | Proc(Int32, Int64)",
        [
          Adamas::MIR::UnionVariantDescriptor.new(1, Adamas::MIR::TypeRef.from_hir(proc_i32_ref), "Proc(Int32, Int32)", 8, 8, nil),
          Adamas::MIR::UnionVariantDescriptor.new(2, Adamas::MIR::TypeRef.from_hir(proc_i64_ref), "Proc(Int32, Int64)", 8, 8, nil),
          Adamas::MIR::UnionVariantDescriptor.new(0, Adamas::MIR::TypeRef::NIL, "Nil", 0, 1, nil),
        ],
        16,
        8
      )
      result_descriptor = Adamas::MIR::UnionDescriptor.new(
        "Nil | Int32",
        [
          Adamas::MIR::UnionVariantDescriptor.new(Adamas::MIR::TypeRef::INT32.id.to_i32, Adamas::MIR::TypeRef::INT32, "Int32", 4, 4, nil),
          Adamas::MIR::UnionVariantDescriptor.new(0, Adamas::MIR::TypeRef::NIL, "Nil", 0, 1, nil),
        ],
        16,
        8
      )
      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.register_union_types([
        Adamas::HIR::UnionDescriptorRegistration.new(Adamas::MIR::TypeRef.from_hir(block_ref), descriptor),
        Adamas::HIR::UnionDescriptorRegistration.new(Adamas::MIR::TypeRef.from_hir(result_ref), result_descriptor),
      ])

      lowering.__test_proc_callback_return_hir_type(block_ref).should be_nil
      expect_raises(Exception, /yield callback ABI unresolved/) do
        lowering.lower
      end
    end

    it "preserves the heap Proc argument ABI on both env branches" do
      lowering = Adamas::MIR::HIRToMIRLowering.new(Adamas::HIR::Module.new("heap_proc_indirect_abi"))
      calls = lowering.__test_heap_proc_indirect_calls
      calls.size.should eq(2)
      calls.each { |call| call.unwrap_union_args.should be_false }
    end

    it "uses the concrete yield type when an unannotated block keeps a Nil or Void return descriptor" do
      [Adamas::HIR::TypeRef::NIL, Adamas::HIR::TypeRef::VOID].each do |stale_return|
        hir_mod = Adamas::HIR::Module.new("unannotated_proc_yield_callback_return_#{stale_return.id}")
        block_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
          Adamas::HIR::TypeKind::Proc,
          "Proc",
          [Adamas::HIR::TypeRef::INT32, stale_return]
        ))
        func = hir_mod.create_function("invoke$unannotated_block", Adamas::HIR::TypeRef::CHAR)
        block_param = func.add_param("block", block_ref, true)
        block = func.get_block(func.entry_block)
        arg = Adamas::HIR::Literal.new(func.next_value_id, Adamas::HIR::TypeRef::INT32, 51_i64)
        block.add(arg)
        yld = Adamas::HIR::Yield.new(
          func.next_value_id,
          Adamas::HIR::TypeRef::CHAR,
          [arg.id],
          block_param.id
        )
        block.add(yld)
        block.terminator = Adamas::HIR::Return.new(yld.id)

        mir_mod = Adamas::MIR::HIRToMIRLowering.new(hir_mod).lower
        mir_func = mir_mod.functions.find { |candidate| candidate.name == "invoke$unannotated_block" }.not_nil!
        indirect = mir_func.blocks
          .flat_map(&.instructions)
          .select(&.is_a?(Adamas::MIR::IndirectCall))
          .first
          .not_nil!
          .as(Adamas::MIR::IndirectCall)
        indirect.type.should eq(Adamas::MIR::TypeRef::CHAR)
      end
    end

    it "calls the raw callback with its concrete return ABI and wraps the yield result" do
      hir_mod = Adamas::HIR::Module.new("proc_yield_callback_lowering")
      proc_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Proc,
        "Proc",
        [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32]
      ))
      block_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Union,
        "Nil | Proc(Int32, Int32)"
      ))
      result_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Union,
        "Nil | Int32"
      ))
      func = hir_mod.create_function("invoke$block", result_ref)
      block_param = func.add_param("block", block_ref, true)
      block = func.get_block(func.entry_block)
      arg = Adamas::HIR::Literal.new(func.next_value_id, Adamas::HIR::TypeRef::INT32, 1_i64)
      block.add(arg)
      yld = Adamas::HIR::Yield.new(func.next_value_id, result_ref, [arg.id], block_param.id)
      block.add(yld)
      block.terminator = Adamas::HIR::Return.new(yld.id)

      block_mir_ref = Adamas::MIR::TypeRef.from_hir(block_ref)
      proc_mir_ref = Adamas::MIR::TypeRef.from_hir(proc_ref)
      result_mir_ref = Adamas::MIR::TypeRef.from_hir(result_ref)
      block_descriptor = Adamas::MIR::UnionDescriptor.new(
        "Nil | Proc(Int32, Int32)",
        [
          Adamas::MIR::UnionVariantDescriptor.new(1, proc_mir_ref, "Proc(Int32, Int32)", 8, 8, nil),
          Adamas::MIR::UnionVariantDescriptor.new(0, Adamas::MIR::TypeRef::NIL, "Nil", 0, 1, nil),
        ],
        16,
        8
      )
      result_descriptor = Adamas::MIR::UnionDescriptor.new(
        "Nil | Int32",
        [
          Adamas::MIR::UnionVariantDescriptor.new(Adamas::MIR::TypeRef::INT32.id.to_i32, Adamas::MIR::TypeRef::INT32, "Int32", 4, 4, nil),
          Adamas::MIR::UnionVariantDescriptor.new(0, Adamas::MIR::TypeRef::NIL, "Nil", 0, 1, nil),
        ],
        16,
        8
      )
      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.register_union_types([
        Adamas::HIR::UnionDescriptorRegistration.new(block_mir_ref, block_descriptor),
        Adamas::HIR::UnionDescriptorRegistration.new(result_mir_ref, result_descriptor),
      ])

      mir_mod = lowering.lower
      mir_func = mir_mod.functions.find { |candidate| candidate.name == "invoke$block" }.not_nil!
      instructions = mir_func.blocks.flat_map(&.instructions)
      indirect = instructions.select(&.is_a?(Adamas::MIR::IndirectCall)).first.not_nil!.as(Adamas::MIR::IndirectCall)
      indirect.type.should eq(Adamas::MIR::TypeRef::INT32)
      indirect.unwrap_union_args.should be_true
      wrapped = instructions.select(&.is_a?(Adamas::MIR::UnionWrap)).first.not_nil!.as(Adamas::MIR::UnionWrap)
      wrapped.type.should eq(result_mir_ref)
      wrapped.value.should eq(indirect.id)
      wrapped.variant_type_id.should eq(Adamas::MIR::TypeRef::INT32.id.to_i32)
    end
  end

  describe "virtual method family resolution" do
    it "keeps an exact concrete generic target direct through an erased receiver" do
      hir_mod = Adamas::HIR::Module.new("exact_generic_target_with_erased_receiver")
      box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox"
      ))
      int_box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox(Int32)"
      ))
      string_box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox(String)"
      ))
      hir_mod.register_generic_dispatch_template("LayoutBox")
      hir_mod.register_generic_instance("LayoutBox", "LayoutBox(Int32)")
      hir_mod.register_generic_instance("LayoutBox", "LayoutBox(String)")

      target = hir_mod.create_function("LayoutBox(Int32)#size", Adamas::HIR::TypeRef::INT32)
      target.add_param("self", int_box_ref)
      target_block = target.get_block(target.entry_block)
      target_value = Adamas::HIR::Literal.new(
        target.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        11_i64
      )
      target_block.add(target_value)
      target_block.terminator = Adamas::HIR::Return.new(target_value.id)
      incompatible_sibling = hir_mod.create_function(
        "LayoutBox(String)#size",
        Adamas::HIR::TypeRef::STRING
      )
      incompatible_sibling.add_param("self", string_box_ref)
      sibling_block = incompatible_sibling.get_block(incompatible_sibling.entry_block)
      sibling_value = Adamas::HIR::Literal.new(
        incompatible_sibling.next_value_id,
        Adamas::HIR::TypeRef::STRING,
        "incompatible"
      )
      sibling_block.add(sibling_value)
      sibling_block.terminator = Adamas::HIR::Return.new(sibling_value.id)
      hir_mod.mark_virtual_dispatch_target_function(target.name)
      hir_mod.mark_virtual_dispatch_target_function(incompatible_sibling.name)

      caller = hir_mod.create_function("exact_generic_caller", Adamas::HIR::TypeRef::INT32)
      receiver = caller.add_param("receiver", box_ref)
      caller_block = caller.get_block(caller.entry_block)
      call = Adamas::HIR::Call.with_receiver(
        caller.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        receiver.id,
        target.name,
        [] of Adamas::HIR::ValueId
      )
      caller_block.add(call)
      caller_block.terminator = Adamas::HIR::Return.new(call.id)

      virtual_caller = hir_mod.create_function(
        "exact_generic_virtual_caller",
        Adamas::HIR::TypeRef::INT32
      )
      virtual_receiver = virtual_caller.add_param("receiver", box_ref)
      virtual_caller_block = virtual_caller.get_block(virtual_caller.entry_block)
      virtual_call = Adamas::HIR::Call.with_receiver_virtual(
        virtual_caller.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        virtual_receiver.id,
        target.name,
        [] of Adamas::HIR::ValueId,
        true
      )
      virtual_caller_block.add(virtual_call)
      virtual_caller_block.terminator = Adamas::HIR::Return.new(virtual_call.id)

      mir_mod = Adamas::MIR::HIRToMIRLowering.new(hir_mod).lower
      [caller.name, virtual_caller.name].each do |caller_name|
        mir_caller = mir_mod.functions.find { |function| function.name == caller_name }.not_nil!
        mir_call = mir_caller.blocks
          .flat_map(&.instructions)
          .find(&.is_a?(Adamas::MIR::Call))
          .not_nil!
          .as(Adamas::MIR::Call)
        callee = mir_mod.functions.find { |function| function.id == mir_call.callee }.not_nil!
        callee.name.should eq(target.name)
      end
    end

    it "includes every HIR-admitted bare generic instance with a unanimous ABI" do
      hir_mod = Adamas::HIR::Module.new("bare_generic_virtual_dispatch")
      box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox"
      ))
      int_box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox(Int32)"
      ))
      string_box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox(String)"
      ))
      bool_box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox(Bool)"
      ))
      hir_mod.register_generic_dispatch_template("LayoutBox")
      hir_mod.register_generic_instance("LayoutBox", "LayoutBox(Int32)")
      hir_mod.register_generic_instance("LayoutBox", "LayoutBox(String)")
      hir_mod.register_generic_instance("LayoutBox", "LayoutBox(Bool)")

      int_getter = hir_mod.create_function("LayoutBox(Int32)#size", Adamas::HIR::TypeRef::INT32)
      int_getter.add_param("self", int_box_ref)
      int_getter_block = int_getter.get_block(int_getter.entry_block)
      int_size = Adamas::HIR::Literal.new(int_getter.next_value_id, Adamas::HIR::TypeRef::INT32, 11_i64)
      int_getter_block.add(int_size)
      int_getter_block.terminator = Adamas::HIR::Return.new(int_size.id)
      string_getter = hir_mod.create_function("LayoutBox(String)#size", Adamas::HIR::TypeRef::INT32)
      string_getter.add_param("self", string_box_ref)
      string_getter_block = string_getter.get_block(string_getter.entry_block)
      string_size = Adamas::HIR::Literal.new(string_getter.next_value_id, Adamas::HIR::TypeRef::INT32, 22_i64)
      string_getter_block.add(string_size)
      string_getter_block.terminator = Adamas::HIR::Return.new(string_size.id)
      inactive_bool_getter = hir_mod.create_function("LayoutBox(Bool)#size", Adamas::HIR::TypeRef::STRING)
      inactive_bool_getter.add_param("self", bool_box_ref)
      inactive_bool_getter_block = inactive_bool_getter.get_block(inactive_bool_getter.entry_block)
      inactive_bool_size = Adamas::HIR::Literal.new(
        inactive_bool_getter.next_value_id,
        Adamas::HIR::TypeRef::STRING,
        "inactive"
      )
      inactive_bool_getter_block.add(inactive_bool_size)
      inactive_bool_getter_block.terminator = Adamas::HIR::Return.new(inactive_bool_size.id)
      hir_mod.mark_virtual_dispatch_target_function(int_getter.name)
      hir_mod.mark_virtual_dispatch_target_function(string_getter.name)

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.prepare
      int_mir_type = lowering.mir_module.type_registry.create_type(
        Adamas::MIR::TypeKind::Reference,
        "LayoutBox(Int32)",
        8_u64,
        8_u32
      )
      string_mir_type = lowering.mir_module.type_registry.create_type(
        Adamas::MIR::TypeKind::Reference,
        "LayoutBox(String)",
        8_u64,
        8_u32
      )
      lowering.mir_module.type_registry.create_type(
        Adamas::MIR::TypeKind::Reference,
        "LayoutBox(Bool)",
        8_u64,
        8_u32
      )

      box_desc = hir_mod.get_type_descriptor(box_ref).not_nil!
      ids = lowering.__test_virtual_dispatch_candidate_type_ids(box_desc, box_ref, "size", 0)
      ids.should contain(int_mir_type.id.to_i32)
      ids.should contain(string_mir_type.id.to_i32)
      ids.size.should eq(2)
    end

    it "rejects a bare generic family with no HIR-admitted targets" do
      hir_mod = Adamas::HIR::Module.new("bare_generic_virtual_dispatch_no_targets")
      box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox"
      ))
      int_box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox(Int32)"
      ))
      hir_mod.register_generic_dispatch_template("LayoutBox")
      hir_mod.register_generic_instance("LayoutBox", "LayoutBox(Int32)")

      inactive_getter = hir_mod.create_function("LayoutBox(Int32)#size", Adamas::HIR::TypeRef::INT32)
      inactive_getter.add_param("self", int_box_ref)
      inactive_getter_block = inactive_getter.get_block(inactive_getter.entry_block)
      inactive_size = Adamas::HIR::Literal.new(
        inactive_getter.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        11_i64
      )
      inactive_getter_block.add(inactive_size)
      inactive_getter_block.terminator = Adamas::HIR::Return.new(inactive_size.id)

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.prepare
      lowering.mir_module.type_registry.create_type(
        Adamas::MIR::TypeKind::Reference,
        "LayoutBox(Int32)",
        8_u64,
        8_u32
      )

      box_desc = hir_mod.get_type_descriptor(box_ref).not_nil!
      ids = lowering.__test_virtual_dispatch_candidate_type_ids(box_desc, box_ref, "size", 0)
      ids.should be_empty
    end

    it "rejects a bare generic dispatch with instance-dependent return ABI" do
      hir_mod = Adamas::HIR::Module.new("bare_generic_virtual_dispatch_abi_guard")
      box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox"
      ))
      int_box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox(Int32)"
      ))
      string_box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "LayoutBox(String)"
      ))
      hir_mod.register_generic_dispatch_template("LayoutBox")
      hir_mod.register_generic_instance("LayoutBox", "LayoutBox(Int32)")
      hir_mod.register_generic_instance("LayoutBox", "LayoutBox(String)")

      int_getter = hir_mod.create_function("LayoutBox(Int32)#payload", Adamas::HIR::TypeRef::INT32)
      int_getter.add_param("self", int_box_ref)
      int_getter_block = int_getter.get_block(int_getter.entry_block)
      int_payload = Adamas::HIR::Literal.new(int_getter.next_value_id, Adamas::HIR::TypeRef::INT32, 1_i64)
      int_getter_block.add(int_payload)
      int_getter_block.terminator = Adamas::HIR::Return.new(int_payload.id)
      string_getter = hir_mod.create_function("LayoutBox(String)#payload", Adamas::HIR::TypeRef::STRING)
      string_getter.add_param("self", string_box_ref)
      string_getter_block = string_getter.get_block(string_getter.entry_block)
      string_payload = Adamas::HIR::Literal.new(string_getter.next_value_id, Adamas::HIR::TypeRef::STRING, "x")
      string_getter_block.add(string_payload)
      string_getter_block.terminator = Adamas::HIR::Return.new(string_payload.id)
      hir_mod.mark_virtual_dispatch_target_function(int_getter.name)
      hir_mod.mark_virtual_dispatch_target_function(string_getter.name)

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.prepare
      lowering.mir_module.type_registry.create_type(
        Adamas::MIR::TypeKind::Reference,
        "LayoutBox(Int32)",
        8_u64,
        8_u32
      )
      lowering.mir_module.type_registry.create_type(
        Adamas::MIR::TypeKind::Reference,
        "LayoutBox(String)",
        8_u64,
        8_u32
      )

      box_desc = hir_mod.get_type_descriptor(box_ref).not_nil!
      ids = lowering.__test_virtual_dispatch_candidate_type_ids(box_desc, box_ref, "payload", 0)
      ids.should be_empty
    end

    it "resolves a typed call through a unique arity alias" do
      hir_mod = Adamas::HIR::Module.new("virtual_method_family")
      func = hir_mod.create_function("IO::FileDescriptor#write$arity1", Adamas::HIR::TypeRef::VOID)
      func.add_param("self", Adamas::HIR::TypeRef::POINTER)
      func.add_param("slice", Adamas::HIR::TypeRef::POINTER)
      competing_string = hir_mod.create_function("IO::FileDescriptor#write$String", Adamas::HIR::TypeRef::VOID)
      competing_string.add_param("self", Adamas::HIR::TypeRef::POINTER)
      competing_string.add_param("string", Adamas::HIR::TypeRef::POINTER)

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.prepare

      resolved = lowering.__test_resolve_virtual_method_for_class(
        "IO::FileDescriptor",
        "write$Slice(UInt8)",
        1,
        true
      )
      resolved.should_not be_nil
      resolved.not_nil!.name.should eq("IO::FileDescriptor#write$arity1")
    end

    it "keeps a module includer's arity alias in vdispatch candidates" do
      hir_mod = Adamas::HIR::Module.new("virtual_dispatch_candidates")
      io_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Module, "IO"))
      hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "IO::FileDescriptor"))
      hir_mod.register_module_includer("IO", "IO::FileDescriptor")

      func = hir_mod.create_function("IO::FileDescriptor#write$arity1", Adamas::HIR::TypeRef::VOID)
      func.add_param("self", Adamas::HIR::TypeRef::POINTER)
      func.add_param("slice", Adamas::HIR::TypeRef::POINTER)
      competing = hir_mod.create_function("IO::FileDescriptor#write$String", Adamas::HIR::TypeRef::VOID)
      competing.add_param("self", Adamas::HIR::TypeRef::POINTER)
      competing.add_param("string", Adamas::HIR::TypeRef::POINTER)

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.prepare
      lowering.mir_module.type_registry.create_type(
        Adamas::MIR::TypeKind::Reference,
        "IO::FileDescriptor",
        8_u64,
        8_u32
      )

      direct = lowering.__test_resolve_virtual_method_for_class(
        "IO::FileDescriptor",
        "write$Slice(UInt8)",
        1,
        true
      )
      direct.should_not be_nil
      io_desc = hir_mod.get_type_descriptor(io_ref).not_nil!
      ids = lowering.__test_virtual_dispatch_candidate_type_ids(
        io_desc,
        io_ref,
        "write$Slice(UInt8)",
        1
      )
      fd_type = lowering.mir_module.type_registry.get_by_name("IO::FileDescriptor")
      fd_type.should_not be_nil, ids.inspect
      ids.should contain(fd_type.not_nil!.id.to_i32)
    end

    it "does not admit a concrete value owner to an Object class dispatch" do
      hir_mod = Adamas::HIR::Module.new("value_owner_virtual_dispatch")
      object_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "Object"))
      module_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Module, "M"))
      value_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "Value"))
      struct_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "Struct"))
      box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "Box"))
      fallback_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "FallbackRef"))
      array_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Array,
        "Array(Int32)",
        [Adamas::HIR::TypeRef::INT32]
      ))
      pointer_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Pointer,
        "Pointer(Int32)",
        [Adamas::HIR::TypeRef::INT32]
      ))
      color_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Struct,
        "Color"
      ))
      hir_mod.register_class_parent("Value", "Object")
      hir_mod.register_class_parent("Struct", "Value")
      hir_mod.register_class_parent("Box", "Struct")
      hir_mod.register_class_parent("FallbackRef", "Value")
      hir_mod.register_class_parent("Int32", "Value")
      hir_mod.register_class_parent("Array(Int32)", "Object")
      hir_mod.register_class_parent("Pointer(Int32)", "Object")
      hir_mod.register_class_parent("Color", "Value")
      hir_mod.register_module_includer("M", "Array(Int32)")
      hir_mod.register_module_includer("M", "Int32")
      hir_mod.register_module_includer("M", "Pointer(Int32)")
      hir_mod.register_module_includer("M", "Color")

      empty_ivars = [] of Adamas::HIR::IVarInfo
      empty_class_vars = [] of Adamas::HIR::ClassVarInfo
      class_infos = {
        "Object" => Adamas::HIR::ClassInfo.new("Object", object_ref, empty_ivars, empty_class_vars, 8, false, nil),
        "Value"  => Adamas::HIR::ClassInfo.new("Value", value_ref, empty_ivars, empty_class_vars, 0, true, "Object"),
        "Struct" => Adamas::HIR::ClassInfo.new("Struct", struct_ref, empty_ivars, empty_class_vars, 0, true, "Value"),
        "Box"    => Adamas::HIR::ClassInfo.new("Box", box_ref, empty_ivars, empty_class_vars, 0, true, "Struct"),
        "FallbackRef" => Adamas::HIR::ClassInfo.new("FallbackRef", fallback_ref, empty_ivars, empty_class_vars, 8, false, "Value"),
      } of String => Adamas::HIR::ClassInfo

      # Keep a concrete value-owner implementation in the MIR function family;
      # the candidate census must filter it by the MIR value-type kind.
      probe = hir_mod.create_function("Box#probe", Adamas::HIR::TypeRef::INT32)
      probe.add_param("self", box_ref)
      probe_block = probe.get_block(probe.entry_block)
      probe_result = Adamas::HIR::Literal.new(probe.next_value_id, Adamas::HIR::TypeRef::INT32, 0_i64)
      probe_block.add(probe_result)
      probe_block.terminator = Adamas::HIR::Return.new(probe_result.id)
      int_probe = hir_mod.create_function("Int32#probe", Adamas::HIR::TypeRef::INT32)
      int_probe.add_param("self", Adamas::HIR::TypeRef::INT32)
      int_probe_block = int_probe.get_block(int_probe.entry_block)
      int_probe_result = Adamas::HIR::Literal.new(int_probe.next_value_id, Adamas::HIR::TypeRef::INT32, 0_i64)
      int_probe_block.add(int_probe_result)
      int_probe_block.terminator = Adamas::HIR::Return.new(int_probe_result.id)
      array_probe = hir_mod.create_function("Array(Int32)#probe", Adamas::HIR::TypeRef::INT32)
      array_probe.add_param("self", array_ref)
      array_probe_block = array_probe.get_block(array_probe.entry_block)
      array_probe_result = Adamas::HIR::Literal.new(array_probe.next_value_id, Adamas::HIR::TypeRef::INT32, 0_i64)
      array_probe_block.add(array_probe_result)
      array_probe_block.terminator = Adamas::HIR::Return.new(array_probe_result.id)
      pointer_probe = hir_mod.create_function("Pointer(Int32)#probe", Adamas::HIR::TypeRef::INT32)
      pointer_probe.add_param("self", pointer_ref)
      pointer_probe_block = pointer_probe.get_block(pointer_probe.entry_block)
      pointer_probe_result = Adamas::HIR::Literal.new(pointer_probe.next_value_id, Adamas::HIR::TypeRef::INT32, 0_i64)
      pointer_probe_block.add(pointer_probe_result)
      pointer_probe_block.terminator = Adamas::HIR::Return.new(pointer_probe_result.id)
      color_probe = hir_mod.create_function("Color#probe", Adamas::HIR::TypeRef::INT32)
      color_probe.add_param("self", color_ref)
      color_probe_block = color_probe.get_block(color_probe.entry_block)
      color_probe_result = Adamas::HIR::Literal.new(color_probe.next_value_id, Adamas::HIR::TypeRef::INT32, 0_i64)
      color_probe_block.add(color_probe_result)
      color_probe_block.terminator = Adamas::HIR::Return.new(color_probe_result.id)
      fallback_probe = hir_mod.create_function("FallbackRef#fallback", Adamas::HIR::TypeRef::INT32)
      fallback_probe.add_param("self", fallback_ref)
      fallback_probe_block = fallback_probe.get_block(fallback_probe.entry_block)
      fallback_probe_result = Adamas::HIR::Literal.new(fallback_probe.next_value_id, Adamas::HIR::TypeRef::INT32, 0_i64)
      fallback_probe_block.add(fallback_probe_result)
      fallback_probe_block.terminator = Adamas::HIR::Return.new(fallback_probe_result.id)

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.register_class_types(class_infos)
      lowering.register_enum_types(Set{"Color"}, hir_mod.types)
      lowering.prepare
      array_type_ref = Adamas::MIR::TypeRef.from_hir(array_ref)
      array_type = lowering.mir_module.type_registry.create_type_with_id(
        array_type_ref.id,
        Adamas::MIR::TypeKind::Array,
        "Array(Int32)",
        24_u64,
        8_u32
      )
      pointer_type_ref = Adamas::MIR::TypeRef.from_hir(pointer_ref)
      pointer_type = lowering.mir_module.type_registry.create_type_with_id(
        pointer_type_ref.id,
        Adamas::MIR::TypeKind::Pointer,
        "Pointer(Int32)",
        8_u64,
        8_u32
      )

      object_desc = hir_mod.get_type_descriptor(object_ref).not_nil!
      ids = lowering.__test_virtual_dispatch_candidate_type_ids(object_desc, object_ref, "probe", 0)
      box_type = lowering.mir_module.type_registry.get_by_name("Box")
      box_type.should_not be_nil
      box_type.not_nil!.is_value_type?.should be_true
      ids.should_not contain(box_type.not_nil!.id.to_i32)
      int_type = lowering.mir_module.type_registry.get_by_name("Int32")
      int_type.should_not be_nil
      int_type.not_nil!.kind.primitive?.should be_true
      ids.should_not contain(int_type.not_nil!.id.to_i32)
      ids.should contain(array_type.id.to_i32)
      ids.should_not contain(pointer_type.id.to_i32)
      fallback_ids = lowering.__test_virtual_dispatch_candidate_type_ids(object_desc, object_ref, "fallback", 0)
      fallback_type = lowering.mir_module.type_registry.get_by_name("FallbackRef")
      fallback_type.should_not be_nil
      fallback_ids.should contain(fallback_type.not_nil!.id.to_i32)
      # Int32 has no direct `fallback` body; the sibling fallback pass must not
      # re-admit its primitive type id into an object-header dispatch table.
      fallback_int_type = lowering.mir_module.type_registry.get_by_name("Int32")
      fallback_int_type.should_not be_nil
      fallback_ids.should_not contain(fallback_int_type.not_nil!.id.to_i32)
      color_type = lowering.mir_module.type_registry.get_by_name("Color")
      color_type.should_not be_nil
      color_type.not_nil!.kind.should eq(Adamas::MIR::TypeKind::Enum)
      ids.should_not contain(color_type.not_nil!.id.to_i32)

      # Module/generic includer dispatch uses the same object-header switch;
      # reject primitive, raw-pointer, and enum includers while retaining
      # Array(T)'s runtime header representation.
      module_desc = hir_mod.get_type_descriptor(module_ref).not_nil!
      module_ids = lowering.__test_virtual_dispatch_candidate_type_ids(module_desc, module_ref, "probe", 0)
      module_ids.should eq([array_type.id.to_i32])

      # A value-layout class root cannot feed the class-header dispatch path,
      # even when a reference descendant supplies an otherwise valid method.
      invalid_root_call = Adamas::HIR::Call.with_receiver_virtual(
        0_u32,
        Adamas::HIR::TypeRef::INT32,
        0_u32,
        "Value#fallback",
        [] of Adamas::HIR::ValueId,
        true
      )
      value_mir_type = lowering.mir_module.type_registry.get_by_name("Value").not_nil!
      value_mir_type.kind.should eq(Adamas::MIR::TypeKind::Struct)
      Adamas::MIR.runtime_header_backed_type?(value_mir_type).should be_false
      lowering.__test_lower_virtual_dispatch_for_receiver(value_ref, invalid_root_call).should be_nil
      lowering.mir_module.functions.any? { |f| f.name.starts_with?("__vdispatch__Value#fallback") }.should be_false
      mismatched_receiver_call = Adamas::HIR::Call.with_receiver_virtual(
        0_u32,
        Adamas::HIR::TypeRef::INT32,
        0_u32,
        "Object#probe",
        [] of Adamas::HIR::ValueId,
        true
      )
      lowering.__test_ensure_class_dispatch_for_union(
        "Object",
        Adamas::MIR::TypeRef.new(pointer_type.id),
        mismatched_receiver_call
      ).should be_nil

      # The abstract-dispatch synthesis path has its own candidate admission
      # loop.  Keep the same no-header families in that path: only Array(T)
      # and Reference owners may produce object-header switch cases.
      mir_probe = lowering.mir_module.get_function("Box#probe").not_nil!
      mir_int_probe = lowering.mir_module.get_function("Int32#probe").not_nil!
      mir_array_probe = lowering.mir_module.get_function("Array(Int32)#probe").not_nil!
      mir_pointer_probe = lowering.mir_module.get_function("Pointer(Int32)#probe").not_nil!
      mir_color_probe = lowering.mir_module.get_function("Color#probe").not_nil!
      mir_fallback_probe = lowering.mir_module.get_function("FallbackRef#fallback").not_nil!
      probe_candidates = [
        {"Box", mir_probe},
        {"Int32", mir_int_probe},
        {"Array(Int32)", mir_array_probe},
        {"Pointer(Int32)", mir_pointer_probe},
        {"Color", mir_color_probe},
      ] of Tuple(String, Adamas::MIR::Function)
      abstract_dispatch = lowering.__test_synthesize_class_dispatch_for_abstract(
        "Object", "probe", probe_candidates
      )
      abstract_dispatch.should_not be_nil
      abstract_switch = abstract_dispatch.not_nil!.blocks.find { |block| block.terminator.is_a?(Adamas::MIR::Switch) }.not_nil!.terminator
      abstract_switch.should be_a(Adamas::MIR::Switch)
      abstract_cases = abstract_switch.as(Adamas::MIR::Switch).cases.map(&.first)
      abstract_cases.should eq([array_type.id.to_i64])

      # A value-layout root cannot read an object header either.  The helper
      # must refuse to synthesize a dispatcher even when a reference child is
      # otherwise eligible.
      value_root_dispatch = lowering.__test_synthesize_class_dispatch_for_abstract(
        "Value", "fallback", [{"FallbackRef", mir_fallback_probe}]
      )
      value_root_dispatch.should be_nil
    end

    it "rejects no-header nested class candidates from union dispatch" do
      hir_mod = Adamas::HIR::Module.new("nested_union_header_dispatch")
      array_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Array,
        "Array(Int32)",
        [Adamas::HIR::TypeRef::INT32]
      ))
      pointer_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Pointer,
        "Pointer(Int32)",
        [Adamas::HIR::TypeRef::INT32]
      ))
      color_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Struct,
        "Color"
      ))
      array_child_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "ArrayChild"
      ))
      pointer_child_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "PointerChild"
      ))
      color_child_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "ColorChild"
      ))
      int_child_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "IntChild"
      ))
      union_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Union,
        "NestedUnion",
        [array_ref, pointer_ref, color_ref, Adamas::HIR::TypeRef::INT32]
      ))
      hir_mod.register_class_parent("ArrayChild", "Array(Int32)")
      hir_mod.register_class_parent("PointerChild", "Pointer(Int32)")
      hir_mod.register_class_parent("ColorChild", "Color")
      hir_mod.register_class_parent("IntChild", "Int32")

      [
        {"ArrayChild", array_child_ref},
        {"PointerChild", pointer_child_ref},
        {"ColorChild", color_child_ref},
        {"IntChild", int_child_ref}
      ].each do |name, type_ref|
        func = hir_mod.create_function("#{name}#probe", Adamas::HIR::TypeRef::INT32)
        func.add_param("self", type_ref)
      end

      empty_ivars = [] of Adamas::HIR::IVarInfo
      empty_class_vars = [] of Adamas::HIR::ClassVarInfo
      class_infos = {
        "ArrayChild" => Adamas::HIR::ClassInfo.new("ArrayChild", array_child_ref, empty_ivars, empty_class_vars, 8, false, "Array(Int32)"),
        "PointerChild" => Adamas::HIR::ClassInfo.new("PointerChild", pointer_child_ref, empty_ivars, empty_class_vars, 8, false, "Pointer(Int32)"),
        "ColorChild" => Adamas::HIR::ClassInfo.new("ColorChild", color_child_ref, empty_ivars, empty_class_vars, 8, false, "Color"),
        "IntChild" => Adamas::HIR::ClassInfo.new("IntChild", int_child_ref, empty_ivars, empty_class_vars, 8, false, "Int32"),
      } of String => Adamas::HIR::ClassInfo

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.register_class_types(class_infos)
      lowering.register_enum_types(Set{"Color"}, hir_mod.types)
      array_type_ref = Adamas::MIR::TypeRef.from_hir(array_ref)
      array_type = lowering.mir_module.type_registry.create_type_with_id(
        array_type_ref.id,
        Adamas::MIR::TypeKind::Array,
        "Array(Int32)",
        24_u64,
        8_u32
      )
      pointer_type_ref = Adamas::MIR::TypeRef.from_hir(pointer_ref)
      pointer_type = lowering.mir_module.type_registry.create_type_with_id(
        pointer_type_ref.id,
        Adamas::MIR::TypeKind::Pointer,
        "Pointer(Int32)",
        8_u64,
        8_u32
      )
      color_type_ref = Adamas::MIR::TypeRef.from_hir(color_ref)
      int_type_ref = Adamas::MIR::TypeRef::INT32
      union_type_ref = Adamas::MIR::TypeRef.from_hir(union_ref)
      descriptor = Adamas::MIR::UnionDescriptor.new(
        "NestedUnion",
        [
          Adamas::MIR::UnionVariantDescriptor.new(array_type_ref.id.to_i32, array_type_ref, "Array(Int32)", 24, 8, nil),
          Adamas::MIR::UnionVariantDescriptor.new(pointer_type_ref.id.to_i32, pointer_type_ref, "Pointer(Int32)", 8, 8, nil),
          Adamas::MIR::UnionVariantDescriptor.new(color_type_ref.id.to_i32, color_type_ref, "Color", 4, 4, nil),
          Adamas::MIR::UnionVariantDescriptor.new(int_type_ref.id.to_i32, int_type_ref, "Int32", 4, 4, nil),
        ],
        32,
        8
      )
      lowering.register_union_types([
        Adamas::HIR::UnionDescriptorRegistration.new(union_type_ref, descriptor),
      ])
      lowering.prepare

      union_desc = hir_mod.get_type_descriptor(union_ref).not_nil!
      ids = lowering.__test_virtual_dispatch_candidate_type_ids(union_desc, union_ref, "probe", 0)
      ids.should eq([array_type.id.to_i32])
      ids.should_not contain(pointer_type.id.to_i32)
      ids.should_not contain(lowering.mir_module.type_registry.get_by_name("Color").not_nil!.id.to_i32)
      ids.should_not contain(Adamas::MIR::TypeRef::INT32.id.to_i32)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BASIC LOWERING
  # ═══════════════════════════════════════════════════════════════════════════

  describe "basic lowering" do
    it "lowers empty function" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("empty", Adamas::HIR::TypeRef::VOID)
      hir_func.get_block(hir_func.entry_block).terminator = Adamas::HIR::Return.new

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      mir_mod = lowering.lower

      mir_mod.functions.size.should eq(1)
      mir_mod.functions[0].name.should eq("empty")
      mir_mod.functions[0].blocks.size.should be >= 1
      lowering.stats.functions_lowered.should eq(1)
    end

    it "lowers function with parameters" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("add", Adamas::HIR::TypeRef::INT32)
      hir_func.add_param("a", Adamas::HIR::TypeRef::INT32)
      hir_func.add_param("b", Adamas::HIR::TypeRef::INT32)
      hir_func.get_block(hir_func.entry_block).terminator = Adamas::HIR::Return.new

      mir_mod = hir_mod.lower_to_mir

      mir_func = mir_mod.functions[0]
      mir_func.params.size.should eq(2)
      mir_func.params[0].name.should eq("a")
      mir_func.params[1].name.should eq("b")
    end

    it "lowers integer literals" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("const_int", Adamas::HIR::TypeRef::INT64)
      block = hir_func.get_block(hir_func.entry_block)

      lit = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT64, 42_i64)
      block.add(lit)
      block.terminator = Adamas::HIR::Return.new(lit.id)

      mir_mod = hir_mod.lower_to_mir

      mir_block = mir_mod.functions[0].get_block(mir_mod.functions[0].entry_block)
      mir_block.instructions.size.should be >= 1

      const = mir_block.instructions.find { |i| i.is_a?(Adamas::MIR::Constant) }
      const.should_not be_nil
    end

    it "lowers boolean literals" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("const_bool", Adamas::HIR::TypeRef::BOOL)
      block = hir_func.get_block(hir_func.entry_block)

      lit = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::BOOL, true)
      block.add(lit)
      block.terminator = Adamas::HIR::Return.new(lit.id)

      mir_mod = hir_mod.lower_to_mir

      mir_block = mir_mod.functions[0].get_block(mir_mod.functions[0].entry_block)
      const = mir_block.instructions.find { |i| i.is_a?(Adamas::MIR::Constant) }
      const.should_not be_nil
      const.as(Adamas::MIR::Constant).value.should eq(true)
    end

    it "tolerates dangling HIR successor ids during block ordering" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("dangling_successor", Adamas::HIR::TypeRef::VOID)
      entry = hir_func.get_block(hir_func.entry_block)
      scope = entry.scope

      body_block_id = hir_func.create_block(scope)
      body_block = hir_func.get_block(body_block_id)

      entry.terminator = Adamas::HIR::Jump.new(body_block_id)
      body_block.terminator = Adamas::HIR::Jump.new(24_u32)

      mir_mod = hir_mod.lower_to_mir
      mir_func = mir_mod.functions.find { |f| f.name == "dangling_successor" }
      mir_func.should_not be_nil
      mir_func = mir_func.not_nil!

      mir_func.blocks.size.should be >= 3
      mir_func.blocks.any?(&.terminator.is_a?(Adamas::MIR::Unreachable)).should be_true
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ARITHMETIC LOWERING
  # ═══════════════════════════════════════════════════════════════════════════

  describe "arithmetic operations" do
    it "lowers add operation" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("add", Adamas::HIR::TypeRef::INT32)
      block = hir_func.get_block(hir_func.entry_block)

      a = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 10_i64)
      b = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 20_i64)
      add_op = Adamas::HIR::BinaryOperation.new(
        hir_func.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        Adamas::HIR::BinaryOp::Add,
        a.id,
        b.id
      )

      block.add(a)
      block.add(b)
      block.add(add_op)
      block.terminator = Adamas::HIR::Return.new(add_op.id)

      mir_mod = hir_mod.lower_to_mir

      mir_block = mir_mod.functions[0].get_block(mir_mod.functions[0].entry_block)
      binop = mir_block.instructions.find { |i| i.is_a?(Adamas::MIR::BinaryOp) }
      binop.should_not be_nil
      binop.as(Adamas::MIR::BinaryOp).op.should eq(Adamas::MIR::BinOp::Add)
    end

    it "lowers comparison operations" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("compare", Adamas::HIR::TypeRef::BOOL)
      block = hir_func.get_block(hir_func.entry_block)

      a = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 5_i64)
      b = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 10_i64)
      cmp = Adamas::HIR::BinaryOperation.new(
        hir_func.next_value_id,
        Adamas::HIR::TypeRef::BOOL,
        Adamas::HIR::BinaryOp::Lt,
        a.id,
        b.id
      )

      block.add(a)
      block.add(b)
      block.add(cmp)
      block.terminator = Adamas::HIR::Return.new(cmp.id)

      mir_mod = hir_mod.lower_to_mir

      mir_block = mir_mod.functions[0].get_block(mir_mod.functions[0].entry_block)
      binop = mir_block.instructions.find { |i| i.is_a?(Adamas::MIR::BinaryOp) }
      binop.should_not be_nil
      binop.as(Adamas::MIR::BinaryOp).op.should eq(Adamas::MIR::BinOp::Lt)
    end

    it "lowers unary negation" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("negate", Adamas::HIR::TypeRef::INT32)
      block = hir_func.get_block(hir_func.entry_block)

      a = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 42_i64)
      neg = Adamas::HIR::UnaryOperation.new(
        hir_func.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        Adamas::HIR::UnaryOp::Neg,
        a.id
      )

      block.add(a)
      block.add(neg)
      block.terminator = Adamas::HIR::Return.new(neg.id)

      mir_mod = hir_mod.lower_to_mir

      mir_block = mir_mod.functions[0].get_block(mir_mod.functions[0].entry_block)
      unop = mir_block.instructions.find { |i| i.is_a?(Adamas::MIR::UnaryOp) }
      unop.should_not be_nil
      unop.as(Adamas::MIR::UnaryOp).op.should eq(Adamas::MIR::UnOp::Neg)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONTROL FLOW LOWERING
  # ═══════════════════════════════════════════════════════════════════════════

  describe "control flow" do
    it "lowers conditional branch" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("branch", Adamas::HIR::TypeRef::INT32)
      func_scope = hir_func.entry_block

      # Create blocks
      entry_block = hir_func.get_block(hir_func.entry_block)
      then_block_id = hir_func.create_block(0_u32)
      else_block_id = hir_func.create_block(0_u32)

      # Entry: branch on condition
      cond = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::BOOL, true)
      entry_block.add(cond)
      entry_block.terminator = Adamas::HIR::Branch.new(cond.id, then_block_id, else_block_id)

      # Then block: return 1
      then_block = hir_func.get_block(then_block_id)
      one = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 1_i64)
      then_block.add(one)
      then_block.terminator = Adamas::HIR::Return.new(one.id)

      # Else block: return 0
      else_block = hir_func.get_block(else_block_id)
      zero = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 0_i64)
      else_block.add(zero)
      else_block.terminator = Adamas::HIR::Return.new(zero.id)

      mir_mod = hir_mod.lower_to_mir

      mir_func = mir_mod.functions[0]
      mir_func.blocks.size.should be >= 3

      # Check branch terminator
      entry_mir = mir_func.get_block(mir_func.entry_block)
      entry_mir.terminator.should be_a(Adamas::MIR::Branch)
    end

    it "lowers unconditional jump" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("jump", Adamas::HIR::TypeRef::VOID)

      entry_block = hir_func.get_block(hir_func.entry_block)
      target_block_id = hir_func.create_block(0_u32)

      entry_block.terminator = Adamas::HIR::Jump.new(target_block_id)

      target_block = hir_func.get_block(target_block_id)
      target_block.terminator = Adamas::HIR::Return.new

      mir_mod = hir_mod.lower_to_mir

      mir_func = mir_mod.functions[0]
      entry_mir = mir_func.get_block(mir_func.entry_block)
      entry_mir.terminator.should be_a(Adamas::MIR::Jump)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MEMORY ALLOCATION LOWERING
  # ═══════════════════════════════════════════════════════════════════════════

  describe "memory allocation" do
    it "lowers allocation with stack strategy for non-escaping values" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("alloc", Adamas::HIR::TypeRef::VOID)
      block = hir_func.get_block(hir_func.entry_block)

      # Non-escaping allocation
      alloc = Adamas::HIR::Allocate.new(hir_func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      alloc.lifetime = Adamas::HIR::LifetimeTag::StackLocal
      block.add(alloc)
      block.terminator = Adamas::HIR::Return.new

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      mir_mod = lowering.lower

      lowering.stats.stack_allocations.should be >= 1
    end

    it "lowers allocation with ARC strategy for escaping values" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("alloc", Adamas::HIR::TypeRef.new(100_u32))
      block = hir_func.get_block(hir_func.entry_block)

      # Escaping allocation
      alloc = Adamas::HIR::Allocate.new(hir_func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
      block.add(alloc)
      block.terminator = Adamas::HIR::Return.new(alloc.id)

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      mir_mod = lowering.lower

      lowering.stats.arc_allocations.should be >= 1
    end

    it "lowers allocation with GC strategy for cyclic types" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("alloc", Adamas::HIR::TypeRef::VOID)
      block = hir_func.get_block(hir_func.entry_block)

      # Cyclic allocation
      alloc = Adamas::HIR::Allocate.new(hir_func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      alloc.lifetime = Adamas::HIR::LifetimeTag::StackLocal
      alloc.taints = Adamas::HIR::Taint::Cyclic
      block.add(alloc)
      block.terminator = Adamas::HIR::Return.new

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      mir_mod = lowering.lower

      lowering.stats.gc_allocations.should be >= 1
    end

    it "does not increment a fresh ARC allocation whose refcount starts at one" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("arc_alloc", Adamas::HIR::TypeRef.new(100_u32))
      block = hir_func.get_block(hir_func.entry_block)

      alloc = Adamas::HIR::Allocate.new(hir_func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
      block.add(alloc)
      block.terminator = Adamas::HIR::Return.new(alloc.id)

      mir_mod = hir_mod.lower_to_mir

      mir_block = mir_mod.functions[0].get_block(mir_mod.functions[0].entry_block)
      allocation = mir_block.instructions.find { |i| i.is_a?(Adamas::MIR::Alloc) }
      allocation.should_not be_nil
      allocation.not_nil!.as(Adamas::MIR::Alloc).strategy.should eq(Adamas::MIR::MemoryStrategy::ARC)
      rc_inc = mir_block.instructions.find { |i| i.is_a?(Adamas::MIR::RCIncrement) }
      rc_inc.should be_nil
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLOSURE LOWERING
  # ═══════════════════════════════════════════════════════════════════════════

  describe "closure lowering" do
    it "lowers closure with captures" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("make_closure", Adamas::HIR::TypeRef.new(200_u32))
      block = hir_func.get_block(hir_func.entry_block)

      # Create captured variable
      cap_var = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 0_i64)
      block.add(cap_var)

      # Create closure
      closure_block = hir_func.create_block(0_u32)
      captures = [Adamas::HIR::CapturedVar.new(cap_var.id, "x", by_reference: true)]
      closure = Adamas::HIR::MakeClosure.new(
        hir_func.next_value_id,
        Adamas::HIR::TypeRef.new(200_u32),
        closure_block,
        captures
      )
      block.add(closure)
      block.terminator = Adamas::HIR::Return.new(closure.id)

      # Empty closure body
      hir_func.get_block(closure_block).terminator = Adamas::HIR::Return.new

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      mir_mod = lowering.lower

      lowering.stats.closures_lowered.should eq(1)
    end

    it "emits non-atomic RC for normal closures" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("normal_closure", Adamas::HIR::TypeRef.new(200_u32))
      block = hir_func.get_block(hir_func.entry_block)

      # Create captured variable
      cap_var = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 42_i64)
      block.add(cap_var)

      # Create closure WITHOUT ThreadShared taint
      closure_block = hir_func.create_block(0_u32)
      captures = [Adamas::HIR::CapturedVar.new(cap_var.id, "x", by_reference: false)]
      closure = Adamas::HIR::MakeClosure.new(
        hir_func.next_value_id,
        Adamas::HIR::TypeRef.new(200_u32),
        closure_block,
        captures
      )
      # NOT marking as ThreadShared
      block.add(closure)
      block.terminator = Adamas::HIR::Return.new(closure.id)

      hir_func.get_block(closure_block).terminator = Adamas::HIR::Return.new

      mir_mod = hir_mod.lower_to_mir

      mir_block = mir_mod.functions[0].get_block(mir_mod.functions[0].entry_block)
      rc_inc = mir_block.instructions.find { |i| i.is_a?(Adamas::MIR::RCIncrement) }
      rc_inc.should_not be_nil
      rc_inc.as(Adamas::MIR::RCIncrement).atomic.should be_false
    end

    it "emits atomic RC for ThreadShared closures" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("shared_closure", Adamas::HIR::TypeRef.new(200_u32))
      block = hir_func.get_block(hir_func.entry_block)

      # Create captured variable
      cap_var = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 42_i64)
      block.add(cap_var)

      # Create closure WITH ThreadShared taint (as if passed to spawn)
      closure_block = hir_func.create_block(0_u32)
      captures = [Adamas::HIR::CapturedVar.new(cap_var.id, "x", by_reference: false)]
      closure = Adamas::HIR::MakeClosure.new(
        hir_func.next_value_id,
        Adamas::HIR::TypeRef.new(200_u32),
        closure_block,
        captures
      )
      # Mark as ThreadShared (would be set by taint analysis when passed to spawn)
      closure.taints = Adamas::HIR::Taint::ThreadShared
      block.add(closure)
      block.terminator = Adamas::HIR::Return.new(closure.id)

      hir_func.get_block(closure_block).terminator = Adamas::HIR::Return.new

      mir_mod = hir_mod.lower_to_mir

      mir_block = mir_mod.functions[0].get_block(mir_mod.functions[0].entry_block)
      rc_inc = mir_block.instructions.find { |i| i.is_a?(Adamas::MIR::RCIncrement) }
      rc_inc.should_not be_nil
      rc_inc.as(Adamas::MIR::RCIncrement).atomic.should be_true

      # Also check that Alloc uses AtomicARC strategy
      alloc = mir_block.instructions.find { |i| i.is_a?(Adamas::MIR::Alloc) }
      alloc.should_not be_nil
      alloc.as(Adamas::MIR::Alloc).strategy.should eq(Adamas::MIR::MemoryStrategy::AtomicARC)
    end

    it "emits AtomicARC for closure with mutable by-ref capture when ThreadShared" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("byref_shared", Adamas::HIR::TypeRef.new(200_u32))
      block = hir_func.get_block(hir_func.entry_block)

      # Create captured mutable variable
      cap_var = Adamas::HIR::Allocate.new(hir_func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      block.add(cap_var)

      # Create closure with by-reference capture AND ThreadShared taint
      closure_block = hir_func.create_block(0_u32)
      captures = [Adamas::HIR::CapturedVar.new(cap_var.id, "state", by_reference: true)]
      closure = Adamas::HIR::MakeClosure.new(
        hir_func.next_value_id,
        Adamas::HIR::TypeRef.new(200_u32),
        closure_block,
        captures
      )
      closure.taints = Adamas::HIR::Taint::ThreadShared | Adamas::HIR::Taint::Mutable
      block.add(closure)
      block.terminator = Adamas::HIR::Return.new(closure.id)

      hir_func.get_block(closure_block).terminator = Adamas::HIR::Return.new

      mir_mod = hir_mod.lower_to_mir

      mir_block = mir_mod.functions[0].get_block(mir_mod.functions[0].entry_block)

      # Find all Allocs - should have 2: one for captured var, one for closure env
      allocs = mir_block.instructions.select { |i| i.is_a?(Adamas::MIR::Alloc) }
      allocs.size.should be >= 1

      # Closure env alloc should use AtomicARC
      env_alloc = allocs.find { |a| a.as(Adamas::MIR::Alloc).strategy == Adamas::MIR::MemoryStrategy::AtomicARC }
      env_alloc.should_not be_nil
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHI NODE LOWERING
  # ═══════════════════════════════════════════════════════════════════════════

  describe "phi node lowering" do
    it "lowers phi nodes with incoming edges" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("phi_test", Adamas::HIR::TypeRef::INT32)

      entry_block = hir_func.get_block(hir_func.entry_block)
      then_block_id = hir_func.create_block(0_u32)
      else_block_id = hir_func.create_block(0_u32)
      merge_block_id = hir_func.create_block(0_u32)

      # Entry: branch
      cond = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::BOOL, true)
      entry_block.add(cond)
      entry_block.terminator = Adamas::HIR::Branch.new(cond.id, then_block_id, else_block_id)

      # Then: value 1
      then_block = hir_func.get_block(then_block_id)
      val1 = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 1_i64)
      then_block.add(val1)
      then_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

      # Else: value 2
      else_block = hir_func.get_block(else_block_id)
      val2 = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 2_i64)
      else_block.add(val2)
      else_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

      # Merge: phi node
      merge_block = hir_func.get_block(merge_block_id)
      phi = Adamas::HIR::Phi.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32)
      phi.add_incoming(then_block_id, val1.id)
      phi.add_incoming(else_block_id, val2.id)
      merge_block.add(phi)
      merge_block.terminator = Adamas::HIR::Return.new(phi.id)

      mir_mod = hir_mod.lower_to_mir

      mir_func = mir_mod.functions[0]
      mir_func.blocks.size.should be >= 4

      # Check predecessors are computed
      mir_func.compute_predecessors
      merge_mir = mir_func.blocks.find { |b| b.instructions.any? { |i| i.is_a?(Adamas::MIR::Phi) } }
      merge_mir.should_not be_nil
    end

    it "wraps non-union incoming values for union phi nodes" do
      hir_mod = Adamas::HIR::Module.new("test")
      union_desc = Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Union, "PtrOrNil")
      hir_union_ref = hir_mod.intern_type(union_desc)

      hir_func = hir_mod.create_function("phi_union_ptr", hir_union_ref)
      entry_block = hir_func.get_block(hir_func.entry_block)
      then_block_id = hir_func.create_block(0_u32)
      else_block_id = hir_func.create_block(0_u32)
      merge_block_id = hir_func.create_block(0_u32)

      cond = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::BOOL, true)
      entry_block.add(cond)
      entry_block.terminator = Adamas::HIR::Branch.new(cond.id, then_block_id, else_block_id)

      then_block = hir_func.get_block(then_block_id)
      ptr_val = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::POINTER, nil)
      then_block.add(ptr_val)
      then_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

      else_block = hir_func.get_block(else_block_id)
      nil_val = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::NIL, nil)
      else_block.add(nil_val)
      else_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

      merge_block = hir_func.get_block(merge_block_id)
      phi = Adamas::HIR::Phi.new(hir_func.next_value_id, hir_union_ref)
      phi.add_incoming(then_block_id, ptr_val.id)
      phi.add_incoming(else_block_id, nil_val.id)
      merge_block.add(phi)
      merge_block.terminator = Adamas::HIR::Return.new(phi.id)

      mir_union_ref = Adamas::MIR::TypeRef.new(hir_union_ref.id + 20_u32)
      mir_union_desc = Adamas::MIR::UnionDescriptor.new(
        "PtrOrNil",
        [
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: Adamas::MIR::TypeRef::POINTER.id.to_i32,
            type_ref: Adamas::MIR::TypeRef::POINTER,
            full_name: "Pointer",
            size: 8,
            alignment: 8,
            field_offsets: nil
          ),
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 0,
            type_ref: Adamas::MIR::TypeRef::NIL,
            full_name: "Nil",
            size: 0,
            alignment: 1,
            field_offsets: nil
          ),
        ],
        16,
        8
      )

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.register_union_types([
        Adamas::HIR::UnionDescriptorRegistration.new(mir_union_ref, mir_union_desc),
      ])
      mir_mod = lowering.lower

      mir_func = mir_mod.functions.find { |f| f.name == "phi_union_ptr" }
      mir_func.should_not be_nil
      mir_func = mir_func.not_nil!

      phi_inst = mir_func.blocks.flat_map(&.instructions).find { |i| i.is_a?(Adamas::MIR::Phi) }
      phi_inst.should_not be_nil
      phi_inst = phi_inst.not_nil!.as(Adamas::MIR::Phi)
      phi_inst.type.should eq(mir_union_ref)

      variant_ids = [] of Int32
      phi_inst.incoming.each do |(block_id, value_id)|
        block = mir_func.get_block(block_id)
        wrap = block.instructions.find { |i| i.is_a?(Adamas::MIR::UnionWrap) && i.id == value_id }
        wrap.should_not be_nil
        mir_wrap = wrap.not_nil!.as(Adamas::MIR::UnionWrap)
        mir_wrap.type.should eq(mir_union_ref)
        variant_ids << mir_wrap.variant_type_id
      end
      variant_ids.sort.should eq([0, Adamas::MIR::TypeRef::POINTER.id.to_i32])
    end
  end

  describe "union unwrap lowering" do
    it "uses the descriptor variant type when unwrap type is still union" do
      hir_mod = Adamas::HIR::Module.new("test")
      union_desc = Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Union, "PtrOrNil")
      hir_union_ref = hir_mod.intern_type(union_desc)

      hir_func = hir_mod.create_function("union_unwrap_ptr", hir_union_ref)
      block = hir_func.get_block(hir_func.entry_block)

      ptr_val = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::POINTER, nil)
      block.add(ptr_val)

      pointer_variant_id = Adamas::MIR::TypeRef::POINTER.id.to_i32
      wrap = Adamas::HIR::UnionWrap.new(hir_func.next_value_id, hir_union_ref, ptr_val.id, pointer_variant_id)
      block.add(wrap)

      unwrap = Adamas::HIR::UnionUnwrap.new(hir_func.next_value_id, hir_union_ref, wrap.id, pointer_variant_id)
      block.add(unwrap)
      block.terminator = Adamas::HIR::Return.new(unwrap.id)

      mir_union_ref = Adamas::MIR::TypeRef.new(hir_union_ref.id + 20_u32)
      mir_union_desc = Adamas::MIR::UnionDescriptor.new(
        "PtrOrNil",
        [
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: pointer_variant_id,
            type_ref: Adamas::MIR::TypeRef::POINTER,
            full_name: "Pointer",
            size: 8,
            alignment: 8,
            field_offsets: nil
          ),
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 0,
            type_ref: Adamas::MIR::TypeRef::NIL,
            full_name: "Nil",
            size: 0,
            alignment: 1,
            field_offsets: nil
          ),
        ],
        16,
        8
      )

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.register_union_types([
        Adamas::HIR::UnionDescriptorRegistration.new(mir_union_ref, mir_union_desc),
      ])

      # The append-only sidecar is authoritative. Poison the legacy Hash with a
      # descriptor that maps the same discriminator to the wrong payload type;
      # lowering must still unwrap the Pointer variant registered above.
      lowering.mir_module.union_descriptors[mir_union_ref] = Adamas::MIR::UnionDescriptor.new(
        "PoisonedPtrOrNil",
        [
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: pointer_variant_id,
            type_ref: Adamas::MIR::TypeRef::UINT8,
            full_name: "UInt8",
            size: 1,
            alignment: 1,
            field_offsets: nil
          ),
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 0,
            type_ref: Adamas::MIR::TypeRef::NIL,
            full_name: "Nil",
            size: 0,
            alignment: 1,
            field_offsets: nil
          ),
        ],
        16,
        8
      )
      mir_mod = lowering.lower

      mir_func = mir_mod.functions.find { |f| f.name == "union_unwrap_ptr" }
      mir_func.should_not be_nil
      mir_func = mir_func.not_nil!

      unwrap_inst = mir_func.blocks.flat_map(&.instructions).find { |i| i.is_a?(Adamas::MIR::UnionUnwrap) }
      unwrap_inst.should_not be_nil
      unwrap_inst = unwrap_inst.not_nil!.as(Adamas::MIR::UnionUnwrap)
      unwrap_inst.type.should eq(Adamas::MIR::TypeRef::POINTER)
    end

    it "selects return union variant ids from the sidecar when the legacy Hash is poisoned" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_union_ref = hir_mod.intern_type(
        Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Union, "Int32OrNil")
      )
      hir_func = hir_mod.create_function("poisoned_union_return", hir_union_ref)
      block = hir_func.get_block(hir_func.entry_block)
      value = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 42_i64)
      block.add(value)
      block.terminator = Adamas::HIR::Return.new(value.id)

      mir_union_ref = Adamas::MIR::TypeRef.from_hir(hir_union_ref)
      int32_variant_id = Adamas::MIR::TypeRef::INT32.id.to_i32
      descriptor = Adamas::MIR::UnionDescriptor.new(
        "Int32OrNil",
        [
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: int32_variant_id,
            type_ref: Adamas::MIR::TypeRef::INT32,
            full_name: "Int32",
            size: 4,
            alignment: 4,
            field_offsets: nil
          ),
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 0,
            type_ref: Adamas::MIR::TypeRef::NIL,
            full_name: "Nil",
            size: 0,
            alignment: 1,
            field_offsets: nil
          ),
        ],
        16,
        8
      )

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.register_union_types([
        Adamas::HIR::UnionDescriptorRegistration.new(mir_union_ref, descriptor),
      ])
      lowering.mir_module.union_descriptors[mir_union_ref] = Adamas::MIR::UnionDescriptor.new(
        "PoisonedInt32OrNil",
        [
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 77,
            type_ref: Adamas::MIR::TypeRef::INT32,
            full_name: "Int32",
            size: 4,
            alignment: 4,
            field_offsets: nil
          ),
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 0,
            type_ref: Adamas::MIR::TypeRef::NIL,
            full_name: "Nil",
            size: 0,
            alignment: 1,
            field_offsets: nil
          ),
        ],
        16,
        8
      )

      mir_mod = lowering.lower
      mir_func = mir_mod.functions.find { |func| func.name == "poisoned_union_return" }.not_nil!
      mir_wrap = mir_func.blocks.flat_map(&.instructions).find(&.is_a?(Adamas::MIR::UnionWrap)).not_nil!
        .as(Adamas::MIR::UnionWrap)
      mir_wrap.type.should eq(mir_union_ref)
      mir_wrap.variant_type_id.should eq(int32_variant_id)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # LOWERING STATISTICS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "lowering statistics" do
    it "tracks allocation counts by strategy" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("multi_alloc", Adamas::HIR::TypeRef::VOID)
      block = hir_func.get_block(hir_func.entry_block)

      # Stack allocation
      alloc1 = Adamas::HIR::Allocate.new(hir_func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      alloc1.lifetime = Adamas::HIR::LifetimeTag::StackLocal
      block.add(alloc1)

      # Heap escape -> ARC
      alloc2 = Adamas::HIR::Allocate.new(hir_func.next_value_id, Adamas::HIR::TypeRef.new(101_u32))
      alloc2.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
      block.add(alloc2)

      # Cyclic -> GC
      alloc3 = Adamas::HIR::Allocate.new(hir_func.next_value_id, Adamas::HIR::TypeRef.new(102_u32))
      alloc3.taints = Adamas::HIR::Taint::Cyclic
      block.add(alloc3)

      block.terminator = Adamas::HIR::Return.new

      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      mir_mod = lowering.lower

      lowering.stats.total_allocations.should eq(3)
      lowering.stats.stack_allocations.should eq(1)
      lowering.stats.arc_allocations.should eq(1)
      lowering.stats.gc_allocations.should eq(1)
    end

    it "reports statistics as string" do
      lowering = Adamas::MIR::HIRToMIRLowering.new(Adamas::HIR::Module.new)
      lowering.stats.functions_lowered = 5
      lowering.stats.blocks_lowered = 20
      lowering.stats.values_lowered = 100

      str = lowering.stats.to_s
      str.should contain("Functions: 5")
      str.should contain("Blocks: 20")
      str.should contain("Values: 100")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TYPE CONVERSION
  # ═══════════════════════════════════════════════════════════════════════════

  describe "type conversion" do
    it "converts primitive types correctly" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("types", Adamas::HIR::TypeRef::INT32)
      block = hir_func.get_block(hir_func.entry_block)

      # Different primitive types
      int_lit = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 1_i64)
      float_lit = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::FLOAT64, 3.14_f64)
      bool_lit = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::BOOL, true)

      block.add(int_lit)
      block.add(float_lit)
      block.add(bool_lit)
      block.terminator = Adamas::HIR::Return.new(int_lit.id)

      mir_mod = hir_mod.lower_to_mir

      mir_block = mir_mod.functions[0].get_block(mir_mod.functions[0].entry_block)
      mir_block.instructions.size.should eq(3)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONVENIENCE EXTENSION
  # ═══════════════════════════════════════════════════════════════════════════

  describe "convenience extension" do
    it "allows calling lower_to_mir on HIR module" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("test", Adamas::HIR::TypeRef::VOID)
      hir_func.get_block(hir_func.entry_block).terminator = Adamas::HIR::Return.new

      mir_mod = hir_mod.lower_to_mir

      mir_mod.should be_a(Adamas::MIR::Module)
      mir_mod.functions.size.should eq(1)
    end
  end
end
