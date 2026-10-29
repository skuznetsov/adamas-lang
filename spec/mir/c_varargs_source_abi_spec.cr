require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

module Adamas::MIR
  class LLVMIRGenerator
    def __test_enable_varargs_array_bulk_guard : Nil
      @inline_value_array_storage = true
    end
  end

  def self.varargs_contract_ir(mod : Module) : String
    generator = LLVMIRGenerator.new(mod)
    generator.emit_type_metadata = false
    generator.generate
  end

  describe "source-owned C variadic ABI" do
    it "rejects missing or contradictory HIR declaration evidence" do
      expect_raises(ArgumentError, "missing or inconsistent C variadic signature") do
        HIR::ExternCall.new(0_u32, HIR::TypeRef::INT32, "user_variadic", varargs: true)
      end
      expect_raises(ArgumentError, "missing or inconsistent C variadic signature") do
        HIR::ExternCall.new(0_u32, HIR::TypeRef::INT32, "user_fixed",
          variadic_fixed_types: [] of HIR::TypeRef)
      end
    end

    it "snapshots the selected prefix instead of retaining a caller-owned array" do
      prefix = [HIR::TypeRef::FLOAT32]
      call = HIR::ExternCall.new(0_u32, HIR::TypeRef::INT32, "user_variadic",
        varargs: true, variadic_fixed_types: prefix)
      prefix.clear
      call.variadic_fixed_types.should eq([HIR::TypeRef::FLOAT32])
    end

    it "transports both nonempty and zero-fixed prefixes from HIR to MIR" do
      [([] of HIR::TypeRef), [HIR::TypeRef::INT32]].each do |prefix|
        hir = HIR::Module.new("varargs_transport")
        function = hir.create_function("transport", HIR::TypeRef::INT32)
        args = prefix.map_with_index { |type, index| function.add_param("arg#{index}", type).id }
        call = HIR::ExternCall.new(function.next_value_id, HIR::TypeRef::INT32,
          "arbitrary_c_name", args, true, false, prefix)
        body = function.get_block(function.entry_block)
        body.add(call)
        body.terminator = HIR::Return.new(call.id)

        mir = HIRToMIRLowering.new(hir).lower
        lowered = mir.get_function("transport").not_nil!.blocks.flat_map(&.instructions)
          .find { |instruction| instruction.is_a?(ExternCall) }.not_nil!.as(ExternCall)
        lowered.variadic_fixed_types.should eq(prefix.map { TypeRef::INT32 })
      end
    end

    it "keeps the selected prefix when copy propagation replaces an operand" do
      mod = Module.new("varargs_rewrite")
      function = mod.create_function("rewritten_call", TypeRef::INT32)
      builder = Builder.new(function)
      condition = builder.const_bool(true)
      selected = builder.const_int(7_i64, TypeRef::INT32)
      other = builder.const_int(9_i64, TypeRef::INT32)
      copy = builder.select(condition, selected, other, TypeRef::INT32)
      prefix = [TypeRef::INT32]
      result = builder.extern_call("arbitrary_c_name", [copy], TypeRef::INT32,
        variadic_fixed_types: prefix)
      prefix.clear
      builder.ret(result)

      CopyPropagationPass.new(function).run.should be > 0
      rewritten = function.get_block(function.entry_block).instructions
        .find { |instruction| instruction.is_a?(ExternCall) }.not_nil!.as(ExternCall)
      rewritten.args.should eq([selected])
      rewritten.variadic_fixed_types.should eq([TypeRef::INT32])
      Adamas::MIR.varargs_contract_ir(mod).should contain("call i32 (i32, ...) @arbitrary_c_name(i32")
    end

    it "promotes only tail floats and preserves a fixed Float32 parameter" do
      mod = Module.new("varargs_float_boundary")
      function = mod.create_function("float_boundary", TypeRef::INT32)
      fixed = function.add_param("fixed", TypeRef::FLOAT32)
      tail = function.add_param("tail", TypeRef::FLOAT32)
      builder = Builder.new(function)
      result = builder.extern_call("user_float_tail", [fixed, tail], TypeRef::INT32,
        variadic_fixed_types: [TypeRef::FLOAT32])
      builder.ret(result)

      output = Adamas::MIR.varargs_contract_ir(mod)
      output.should contain("fpext float %tail to double")
      output.should_not contain("fpext float %fixed")
      output.should contain("call i32 (float, ...) @user_float_tail(float %fixed, double")
    end

    it "sign extends signed narrow tail integers and zero extends unsigned ones" do
      mod = Module.new("varargs_integer_promotions")
      function = mod.create_function("integer_promotions", TypeRef::INT32)
      args = [TypeRef::INT8, TypeRef::UINT8, TypeRef::INT16, TypeRef::UINT16]
        .map_with_index { |type, index| function.add_param("arg#{index}", type) }
      builder = Builder.new(function)
      result = builder.extern_call("user_integer_tail", args, TypeRef::INT32,
        variadic_fixed_types: [] of TypeRef)
      builder.ret(result)

      output = Adamas::MIR.varargs_contract_ir(mod)
      output.should contain("sext i8 %arg0 to i32")
      output.should contain("zext i8 %arg1 to i32")
      output.should contain("sext i16 %arg2 to i32")
      output.should contain("zext i16 %arg3 to i32")
      output.should contain("call i32 (...) @user_integer_tail(i32")
    end

    it "retains Crystal's Bool and Char tail representations" do
      mod = Module.new("varargs_noninteger_primitives")
      function = mod.create_function("primitive_tail", TypeRef::INT32)
      boolean = function.add_param("boolean", TypeRef::BOOL)
      char = function.add_param("char", TypeRef::CHAR)
      builder = Builder.new(function)
      result = builder.extern_call("user_primitive_tail", [boolean, char], TypeRef::INT32,
        variadic_fixed_types: [] of TypeRef)
      builder.ret(result)

      output = Adamas::MIR.varargs_contract_ir(mod)
      output.should contain("call i32 (...) @user_primitive_tail(i1 %boolean, i32 %char)")
    end

    it "emits a typed variadic call for Void results and for an empty tail" do
      mod = Module.new("varargs_void")
      function = mod.create_function("void_boundary", TypeRef::VOID)
      fixed = function.add_param("fixed", TypeRef::INT32)
      builder = Builder.new(function)
      builder.extern_call("user_void_tail", [fixed], TypeRef::VOID,
        variadic_fixed_types: [TypeRef::INT32])
      builder.extern_call("user_zero_fixed", ([] of ValueId), TypeRef::VOID,
        variadic_fixed_types: [] of TypeRef)
      builder.ret

      output = Adamas::MIR.varargs_contract_ir(mod)
      output.should contain("call void (i32, ...) @user_void_tail(i32 %fixed)")
      output.should contain("call void (...) @user_zero_fixed()")
      output.should_not contain("(, ...)")
    end

    it "does not infer a variadic ABI from a known libc name" do
      mod = Module.new("fixed_name")
      function = mod.create_function("fixed_call", TypeRef::INT32)
      argument = function.add_param("argument", TypeRef::FLOAT32)
      builder = Builder.new(function)
      result = builder.extern_call("printf", [argument], TypeRef::INT32)
      builder.ret(result)

      output = Adamas::MIR.varargs_contract_ir(mod)
      output.should contain("call i32 @printf(float %argument)")
      output.should_not contain("call i32 (ptr, ...)")
      output.should_not contain("fpext float %argument")
    end

    it "keeps internal inline-array pointer helpers nonvariadic" do
      mod = Module.new("fixed_array_helper")
      function = mod.create_function("inline_array_helper", TypeRef::POINTER)
      dest = function.add_param("dest", TypeRef::POINTER)
      source = function.add_param("source", TypeRef::POINTER)
      builder = Builder.new(function)
      count = builder.const_int(3_i64, TypeRef::INT32)
      old_stride = builder.const_int(8_i64, TypeRef::INT32)
      result = builder.extern_call("__adamas_ptr_copy", [dest, source, count, old_stride], TypeRef::POINTER)
      call = function.get_block(function.entry_block).instructions
        .find { |instruction| instruction.is_a?(ExternCall) }.not_nil!.as(ExternCall)
      call.array_bulk_stride = 12_u32
      builder.ret(result)

      generator = LLVMIRGenerator.new(mod)
      generator.emit_type_metadata = false
      generator.__test_enable_varargs_array_bulk_guard
      output = generator.generate
      output.should contain("call ptr @__adamas_ptr_copy(ptr %dest, ptr %source, i32")
      output.should contain("i32 12) ; ivc_raw bulk-stride")
      output.should_not contain("call ptr (ptr, ptr, i32, i32, ...)")
    end

    it "rejects a MIR call that has lost a fixed argument" do
      mod = Module.new("lost_fixed_argument")
      function = mod.create_function("invalid_call", TypeRef::VOID)
      builder = Builder.new(function)
      builder.extern_call("user_missing_fixed", ([] of ValueId), TypeRef::VOID,
        variadic_fixed_types: [TypeRef::INT32])
      builder.ret

      expect_raises(Exception, "C variadic call user_missing_fixed lost its fixed arguments") do
        Adamas::MIR.varargs_contract_ir(mod)
      end
    end
  end
end
