require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

class Adamas::MIR::DwarfDebugContext
  def __test_stable_metadata_id(key : String, base : Int32, span : Int32) : Int32
    stable_metadata_id(key, base, span)
  end

  def __test_unique_stable_metadata_id(
    assigned_ids : Hash(Int32, String),
    key : String,
    base : Int32,
    span : Int32,
  ) : Int32
    unique_stable_metadata_id(assigned_ids, key, base, span)
  end
end

describe Adamas::MIR::LLVMTypeMapper do
  describe "#llvm_type" do
    it "maps primitive types correctly" do
      registry = Adamas::MIR::TypeRegistry.new
      mapper = Adamas::MIR::LLVMTypeMapper.new(registry)

      mapper.llvm_type(Adamas::MIR::TypeRef::VOID).should eq("void")
      mapper.llvm_type(Adamas::MIR::TypeRef::BOOL).should eq("i1")
      mapper.llvm_type(Adamas::MIR::TypeRef::INT8).should eq("i8")
      mapper.llvm_type(Adamas::MIR::TypeRef::INT16).should eq("i16")
      mapper.llvm_type(Adamas::MIR::TypeRef::INT32).should eq("i32")
      mapper.llvm_type(Adamas::MIR::TypeRef::INT64).should eq("i64")
      mapper.llvm_type(Adamas::MIR::TypeRef::INT128).should eq("i128")
      mapper.llvm_type(Adamas::MIR::TypeRef::UINT8).should eq("i8")
      mapper.llvm_type(Adamas::MIR::TypeRef::UINT32).should eq("i32")
      mapper.llvm_type(Adamas::MIR::TypeRef::FLOAT32).should eq("float")
      mapper.llvm_type(Adamas::MIR::TypeRef::FLOAT64).should eq("double")
      mapper.llvm_type(Adamas::MIR::TypeRef::POINTER).should eq("ptr")
    end

    it "maps struct types to ptr (structs passed by pointer in ABI)" do
      registry = Adamas::MIR::TypeRegistry.new
      struct_type = registry.create_type(Adamas::MIR::TypeKind::Struct, "MyStruct", 16, 8)
      mapper = Adamas::MIR::LLVMTypeMapper.new(registry)

      # Structs are passed by pointer in our ABI for consistency
      mapper.llvm_type(struct_type).should eq("ptr")
    end

    it "maps struct types to named types for alloca" do
      registry = Adamas::MIR::TypeRegistry.new
      struct_type = registry.create_type(Adamas::MIR::TypeKind::Struct, "MyStruct", 16, 8)
      mapper = Adamas::MIR::LLVMTypeMapper.new(registry)

      # For alloca, we need the actual struct type (via TypeRef)
      struct_type_ref = Adamas::MIR::TypeRef.new(struct_type.id)
      mapper.llvm_alloca_type(struct_type_ref).should eq("%MyStruct")
    end

    it "maps reference types to ptr" do
      registry = Adamas::MIR::TypeRegistry.new
      ref_type = registry.create_type(Adamas::MIR::TypeKind::Reference, "MyClass", 8, 8)
      mapper = Adamas::MIR::LLVMTypeMapper.new(registry)

      mapper.llvm_type(ref_type).should eq("ptr")
    end

    it "maps union types with .union suffix" do
      registry = Adamas::MIR::TypeRegistry.new
      union_type = registry.create_type(Adamas::MIR::TypeKind::Union, "IntOrString", 16, 8)
      mapper = Adamas::MIR::LLVMTypeMapper.new(registry)

      mapper.llvm_type(union_type).should eq("%IntOrString.union")
    end

    it "mangles special characters in type names" do
      registry = Adamas::MIR::TypeRegistry.new
      mapper = Adamas::MIR::LLVMTypeMapper.new(registry)

      mapper.mangle_name("Array(Int32)").should eq("Array$LInt32$R")
      mapper.mangle_name("Hash(String, Int32)").should eq("Hash$LString$C$_Int32$R")
    end
  end
end

describe Adamas::MIR::LLVMIRGenerator do
  describe "#generate" do
    it "generates module header" do
      mod = Adamas::MIR::Module.new("test_module")
      mod.source_file = "test.cr"

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("; ModuleID = 'test_module'")
      output.should contain("source_filename = \"test.cr\"")
      output.should contain("target triple")
    end

    it "generates runtime definitions" do
      mod = Adamas::MIR::Module.new("test")
      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      # Runtime functions are now defined with implementations
      output.should contain("define ptr @__adamas_malloc64(i64 %size)")
      output.should contain("define void @__adamas_rc_inc(ptr %ptr)")
      output.should contain("define void @__adamas_rc_dec(ptr %ptr, ptr %destructor)")
      output.should contain("define ptr @__adamas_slab_alloc(i32 %size_class)")
      output.should contain("shl i64 16, %size")
      output.should contain("define void @__adamas_slab_frame_push()")
      output.should contain("define void @__adamas_slab_frame_pop()")
    end

    it "keeps the raw Thread::Mutex initializer target-local" do
      mod = Adamas::MIR::Module.new("thread_mutex_override")
      func = mod.create_function("Thread::Mutex#initialize", Adamas::MIR::TypeRef::VOID)
      func.add_param("self", Adamas::MIR::TypeRef::POINTER)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      gen.target_triple = "arm64-apple-macosx"
      output = gen.generate

      body = output[/define void @Thread\$CCMutex\$Hinitialize\(ptr %self\) \{.*?\n\}/m]
      body.should_not be_nil
      body = body.not_nil!
      body.should contain("call i32 @pthread_mutexattr_settype(ptr %attr, i32 1)")
      body.should_not contain("@LibC__classvar__PTHREAD_MUTEX_ERRORCHECK")
    end

    it "uses byte-stride copy-before-clear only for inline composite Array#pop" do
      mod = Adamas::MIR::Module.new("array_pop_abi")
      registry = mod.type_registry

      tuple_type = registry.create_type(
        Adamas::MIR::TypeKind::Tuple,
        "Tuple(Bool, Bool, Bool)",
        3_u64,
        1_u32
      )
      bool_type = registry.get(Adamas::MIR::TypeRef::BOOL).not_nil!
      3.times { tuple_type.add_element_type(bool_type) }
      tuple_array = registry.create_type(
        Adamas::MIR::TypeKind::Array,
        "Array(Tuple(Bool, Bool, Bool))",
        24_u64,
        8_u32
      )
      tuple_array.set_element_type(tuple_type)

      uint_array = registry.create_type(
        Adamas::MIR::TypeKind::Array,
        "Array(UInt32)",
        24_u64,
        8_u32
      )
      uint_array.set_element_type(registry.get(Adamas::MIR::TypeRef::UINT32).not_nil!)

      pointer_type = registry.create_type(
        Adamas::MIR::TypeKind::Pointer,
        "Pointer(UInt8)",
        8_u64,
        8_u32
      )
      pointer_type.set_element_type(registry.get(Adamas::MIR::TypeRef::UINT8).not_nil!)
      pointer_array = registry.create_type(
        Adamas::MIR::TypeKind::Array,
        "Array(Pointer(UInt8))",
        24_u64,
        8_u32
      )
      pointer_array.set_element_type(pointer_type)

      tuple_pop = mod.create_function("Array(Tuple(Bool, Bool, Bool))#pop", Adamas::MIR::TypeRef::POINTER)
      tuple_pop.add_param("self", Adamas::MIR::TypeRef::POINTER)
      Adamas::MIR::Builder.new(tuple_pop).ret

      uint_pop = mod.create_function("Array(UInt32)#pop", Adamas::MIR::TypeRef::UINT32)
      uint_pop.add_param("self", Adamas::MIR::TypeRef::POINTER)
      uint_builder = Adamas::MIR::Builder.new(uint_pop)
      uint_builder.ret(uint_builder.const_uint(0_u64, Adamas::MIR::TypeRef::UINT32))

      pointer_pop = mod.create_function("Array(Pointer(UInt8))#pop", Adamas::MIR::TypeRef::POINTER)
      pointer_pop.add_param("self", Adamas::MIR::TypeRef::POINTER)
      Adamas::MIR::Builder.new(pointer_pop).ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      tuple_name = "Array$LTuple$LBool$C$_Bool$C$_Bool$R$R$Hpop"
      tuple_body = output[/define ptr @#{Regex.escape(tuple_name)}\([^)]*\) \{.*?\n\}/m]
      tuple_body.should_not be_nil
      tuple_ir = tuple_body.not_nil!
      tuple_ir.should contain("mul i64 %physical64, 3")
      tuple_ir.should contain("llvm.memcpy.p0.p0.i64")
      tuple_ir.should contain("llvm.memset.p0.i64")
      tuple_ir.should contain("raise_empty")
      tuple_ir.should contain("unreachable")
      tuple_ir.should contain("%root_byte_offset")
      tuple_ir.index("llvm.memcpy.p0.p0.i64").not_nil!.should be < tuple_ir.index("llvm.memset.p0.i64").not_nil!

      uint_name = "Array$LUInt32$R$Hpop"
      uint_body = output[/define i32 @#{Regex.escape(uint_name)}\([^)]*\) \{.*?\n\}/m]
      uint_body.should_not be_nil
      uint_body.not_nil!.should_not contain("inline composite pop")
      uint_body.not_nil!.should_not contain("mul i64 %physical64")

      pointer_name = "Array$LPointer$LUInt8$R$R$Hpop"
      pointer_body = output[/define ptr @#{Regex.escape(pointer_name)}\([^)]*\) \{.*?\n\}/m]
      pointer_body.should_not be_nil
      pointer_body.not_nil!.should_not contain("inline composite pop")
    end

    it "manages raw-header union fields but never raw nullable Pointer fields" do
      mod = Adamas::MIR::Module.new("union_dtor_contract")
      registry = mod.type_registry
      header_type = registry.create_type(Adamas::MIR::TypeKind::Reference, "DtorHeader", 8, 8)
      header_ref = Adamas::MIR::TypeRef.new(header_type.id)

      nullable_type = registry.create_type(Adamas::MIR::TypeKind::Union, "Pointer | Nil", 16, 8)
      nullable_ref = Adamas::MIR::TypeRef.new(nullable_type.id)
      mod.register_union(
        nullable_ref,
        Adamas::MIR::UnionDescriptor.new(
          "Pointer | Nil",
          [
            Adamas::MIR::UnionVariantDescriptor.new(
              Adamas::MIR::TypeRef::POINTER.id.to_i32,
              Adamas::MIR::TypeRef::POINTER,
              "Pointer",
              8,
              8,
              nil
            ),
            Adamas::MIR::UnionVariantDescriptor.new(0, Adamas::MIR::TypeRef::NIL, "Nil", 0, 1, nil),
          ],
          16,
          8
        )
      )

      header_union_type = registry.create_type(Adamas::MIR::TypeKind::Union, "DtorHeader | Nil", 16, 8)
      header_union_ref = Adamas::MIR::TypeRef.new(header_union_type.id)
      mod.register_union(
        header_union_ref,
        Adamas::MIR::UnionDescriptor.new(
          "DtorHeader | Nil",
          [
            Adamas::MIR::UnionVariantDescriptor.new(
              header_ref.id.to_i32,
              header_ref,
              "DtorHeader",
              8,
              8,
              nil
            ),
            Adamas::MIR::UnionVariantDescriptor.new(0, Adamas::MIR::TypeRef::NIL, "Nil", 0, 1, nil),
          ],
          16,
          8
        )
      )

      owner = registry.create_type(Adamas::MIR::TypeKind::Reference, "DtorOwner", 24, 8)
      owner.add_field("@raw", nullable_ref, 8_u32)
      owner.add_field("@managed", header_union_ref, 16_u32)
      mod.refresh_union_storage_kinds

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate
      dtor = output[/define void @__adamas_dtor_#{owner.id}\(ptr %obj\) \{.*?\n\}/m].not_nil!

      dtor.should_not contain("i64 8")
      dtor.should contain("i64 16")
      dtor.scan("call void @__adamas_rc_dec").size.should eq(1)
    end

    it "emits entrypoint when __adamas_main is present" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("__adamas_main", Adamas::MIR::TypeRef::VOID)
      builder = Adamas::MIR::Builder.new(func)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      gen.reachability = true
      output = gen.generate

      output.should contain("define i32 @main")
      output.should contain("call void @__adamas_main")
    end

    it "emits slab frame prolog/epilog when enabled" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("foo", Adamas::MIR::TypeRef::VOID)
      func.slab_frame = true
      builder = Adamas::MIR::Builder.new(func)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("call void @__adamas_slab_frame_push()")
      output.should contain("call void @__adamas_slab_frame_pop()")
    end

    it "keeps entrypoint when __adamas_main contains typeof_ extern calls" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("__adamas_main", Adamas::MIR::TypeRef::VOID)
      builder = Adamas::MIR::Builder.new(func)
      args = [] of Adamas::MIR::ValueId
      builder.extern_call("typeof_foo", args, Adamas::MIR::TypeRef::VOID)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      gen.reachability = true
      output = gen.generate

      output.should contain("define i32 @main")
      output.should contain("call void @__adamas_main")
    end

    it "generates simple function" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("add", Adamas::MIR::TypeRef::INT32)
      func.add_param("a", Adamas::MIR::TypeRef::INT32)
      func.add_param("b", Adamas::MIR::TypeRef::INT32)

      builder = Adamas::MIR::Builder.new(func)
      # a + b
      sum = builder.add(0_u32, 1_u32, Adamas::MIR::TypeRef::INT32)
      builder.ret(sum)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("define i32 @add(i32 %a, i32 %b)")
      output.should contain("add i32")
      output.should contain("ret")
    end

    it "keeps a declared Int32 binary result Int32 across a block boundary" do
      mod = Adamas::MIR::Module.new("cross_block_binary_width")

      callee = mod.create_function("takes_int32", Adamas::MIR::TypeRef::INT32)
      callee.add_param("value", Adamas::MIR::TypeRef::INT32)
      Adamas::MIR::Builder.new(callee).ret(0_u32)

      caller = mod.create_function("cross_block_binary_width", Adamas::MIR::TypeRef::INT32)
      caller.add_param("limit", Adamas::MIR::TypeRef::INT32)
      producer = caller.create_block
      continuation = caller.create_block
      builder = Adamas::MIR::Builder.new(caller)
      builder.jump(producer)

      builder.current_block = producer
      missing_rhs = builder.const_int(0, Adamas::MIR::TypeRef::INT64)
      remaining = builder.sub(0_u32, missing_rhs, Adamas::MIR::TypeRef::INT32)
      builder.jump(continuation)

      builder.current_block = continuation
      result = builder.call(callee.id, [remaining], Adamas::MIR::TypeRef::INT32)
      builder.ret(result)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      body = output[/define i32 @cross_block_binary_width\(i32 %limit\)\s*\{.*?\n\}/m]
      body.should_not be_nil
      body = body.not_nil!
      body.should contain("%r2.slot = alloca i32")
      body.should contain("store i32 %r2, ptr %r2.slot")
      body.should match(/%r2\.fromslot\.\d+ = load i32, ptr %r2\.slot/)
      body.should match(/call i32 @takes_int32\(i32 %r2\.fromslot\.\d+\)/)
      body.should_not contain("%r2.slot = alloca i64")
    end

    it "generates stack allocation" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("alloc_test", Adamas::MIR::TypeRef::VOID)

      builder = Adamas::MIR::Builder.new(func)
      ptr = builder.alloc(Adamas::MIR::MemoryStrategy::Stack, Adamas::MIR::TypeRef::INT32, 4_u64, 4_u32)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("alloca i32, align 4")
    end

    it "generates ARC allocation with RC initialization" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("arc_test", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      ptr = builder.alloc(Adamas::MIR::MemoryStrategy::ARC, Adamas::MIR::TypeRef::STRING, 32_u64, 8_u32)
      builder.ret(ptr)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("call ptr @__adamas_malloc64(i64 40)") # 32 + 8 for RC
      output.should contain("store i64 1")                         # Initialize RC to 1
      output.should contain("getelementptr i8")                    # Skip RC to get object pointer
    end

    it "generates slab allocation" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("slab_test", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      ptr = builder.alloc(Adamas::MIR::MemoryStrategy::Slab, Adamas::MIR::TypeRef::INT32, 16_u64, 4_u32)
      builder.ret(ptr)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("call ptr @__adamas_slab_alloc(i32 0)") # Size class 0 for <=16 bytes
    end

    it "generates slab free" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("slab_free_test", Adamas::MIR::TypeRef::VOID)

      builder = Adamas::MIR::Builder.new(func)
      ptr = builder.alloc(Adamas::MIR::MemoryStrategy::Slab, Adamas::MIR::TypeRef::INT32, 16_u64, 4_u32)
      builder.free(ptr, Adamas::MIR::MemoryStrategy::Slab)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("call void @__adamas_slab_free(ptr %")
    end

    it "normalizes union stores to zeroinitializer" do
      mod = Adamas::MIR::Module.new("test")
      union_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Union, "IntOrNil", 16, 8)
      union_ref = Adamas::MIR::TypeRef.new(union_type.id)
      mod.register_union(
        union_ref,
        Adamas::MIR::UnionDescriptor.new(
          "IntOrNil",
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
      )

      func = mod.create_function("union_store", Adamas::MIR::TypeRef::VOID)
      builder = Adamas::MIR::Builder.new(func)
      ptr = builder.alloc(Adamas::MIR::MemoryStrategy::Stack, union_ref, 16_u64, 8_u32)

      block = func.get_block(func.entry_block)
      union_nil = Adamas::MIR::Constant.new(func.next_value_id, union_ref, nil)
      block.add(union_nil)
      builder.store(ptr, union_nil.id)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("store %IntOrNil.union zeroinitializer")
    end

    it "normalizes union nil array element stores to zeroinitializer" do
      mod = Adamas::MIR::Module.new("test")
      union_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Union, "IntOrNil", 16, 8)
      union_ref = Adamas::MIR::TypeRef.new(union_type.id)
      mod.register_union(
        union_ref,
        Adamas::MIR::UnionDescriptor.new(
          "IntOrNil",
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
      )

      func = mod.create_function("union_array_set", Adamas::MIR::TypeRef::VOID)
      array_param = func.add_param("arr", Adamas::MIR::TypeRef::POINTER)
      builder = Adamas::MIR::Builder.new(func)
      index = builder.const_int(0_i64, Adamas::MIR::TypeRef::INT32)

      block = func.get_block(func.entry_block)
      union_nil = Adamas::MIR::Constant.new(func.next_value_id, union_ref, nil)
      block.add(union_nil)
      block.add(Adamas::MIR::ArraySet.new(func.next_value_id, union_ref, array_param, index, union_nil.id))
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("store %IntOrNil.union zeroinitializer")
      output.should_not contain("store %IntOrNil.union 0")
    end

    it "skips emitting SSA values for void casts" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("void_cast", Adamas::MIR::TypeRef::VOID)
      builder = Adamas::MIR::Builder.new(func)
      val = builder.const_int(1_i64, Adamas::MIR::TypeRef::INT32)
      builder.cast(Adamas::MIR::CastKind::Bitcast, val, Adamas::MIR::TypeRef::VOID)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should_not contain("alloca void")
    end

    it "casts ptr to float64 via ptrtoint + uitofp (without dereference)" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("ptr_to_float_cast", Adamas::MIR::TypeRef::FLOAT64)
      func.add_param("p", Adamas::MIR::TypeRef::POINTER)
      builder = Adamas::MIR::Builder.new(func)

      casted = builder.cast(Adamas::MIR::CastKind::Bitcast, 0_u32, Adamas::MIR::TypeRef::FLOAT64)
      builder.ret(casted)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define double @ptr_to_float_cast\(ptr %p\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!

      body.should contain("ptrtoint ptr %p to i64")
      body.should contain("uitofp i64")
      body.should_not contain("load double, ptr %p")
    end

    it "uses zext for unsigned fixed vararg widening in extern call" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("extern_unsigned_widen", Adamas::MIR::TypeRef::INT32)
      func.add_param("fmt", Adamas::MIR::TypeRef::POINTER)
      builder = Adamas::MIR::Builder.new(func)

      dst = builder.const_nil_typed(Adamas::MIR::TypeRef::POINTER)
      len = builder.const_uint(255_u64, Adamas::MIR::TypeRef::UINT32)
      call_args = [dst, len, 0_u32] of Adamas::MIR::ValueId
      res = builder.extern_call("snprintf", call_args, Adamas::MIR::TypeRef::INT32)
      builder.ret(res)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define i32 @extern_unsigned_widen\(ptr %fmt\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!
      cast_lines = body.lines.select(&.includes?("varargs_cast."))
      cast_lines.should_not be_empty
      cast_blob = cast_lines.join("\n")
      cast_blob.should contain("zext i32")
      cast_blob.should_not contain("sext i32")
      body.should contain("call i32 (ptr, i64, ptr, ...) @snprintf(")
    end

    it "uses fptoui for float64 to uint32 cast" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("float_to_uint_cast", Adamas::MIR::TypeRef::UINT32)
      func.add_param("x", Adamas::MIR::TypeRef::FLOAT64)
      builder = Adamas::MIR::Builder.new(func)

      casted = builder.cast(Adamas::MIR::CastKind::Bitcast, 0_u32, Adamas::MIR::TypeRef::UINT32)
      builder.ret(casted)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define i32 @float_to_uint_cast\(double %x\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!
      body.should contain("fptoui double %x to i32")
      body.should_not contain("fptosi double %x to i32")
    end

    it "uses uitofp for uint32 to float64 cast" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("uint_to_float_cast", Adamas::MIR::TypeRef::FLOAT64)
      func.add_param("x", Adamas::MIR::TypeRef::UINT32)
      builder = Adamas::MIR::Builder.new(func)

      casted = builder.cast(Adamas::MIR::CastKind::UIToFP, 0_u32, Adamas::MIR::TypeRef::FLOAT64)
      builder.ret(casted)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define double @uint_to_float_cast\(i32 %x\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!
      body.should contain("uitofp i32 %x to double")
      body.should_not contain("sitofp i32 %x to double")
    end

    it "uses uitofp for uint64 to float64 cast" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("uint64_to_float_cast", Adamas::MIR::TypeRef::FLOAT64)
      func.add_param("x", Adamas::MIR::TypeRef::UINT64)
      builder = Adamas::MIR::Builder.new(func)

      casted = builder.cast(Adamas::MIR::CastKind::UIToFP, 0_u32, Adamas::MIR::TypeRef::FLOAT64)
      builder.ret(casted)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define double @uint64_to_float_cast\(i64 %x\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!
      body.should contain("uitofp i64 %x to double")
      body.should_not contain("sitofp i64 %x to double")
    end

    it "uses uitofp for uint128 to float64 cast" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("uint128_to_float_cast", Adamas::MIR::TypeRef::FLOAT64)
      func.add_param("x", Adamas::MIR::TypeRef::UINT128)
      builder = Adamas::MIR::Builder.new(func)

      casted = builder.cast(Adamas::MIR::CastKind::UIToFP, 0_u32, Adamas::MIR::TypeRef::FLOAT64)
      builder.ret(casted)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define double @uint128_to_float_cast\(i128 %x\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!
      body.should contain("uitofp i128 %x to double")
      body.should_not contain("sitofp i128 %x to double")
    end

    it "uses uitofp for uint32 argument when calling float64 callee" do
      mod = Adamas::MIR::Module.new("test")

      callee = mod.create_function("takes_f64_arg", Adamas::MIR::TypeRef::FLOAT64)
      callee.add_param("x", Adamas::MIR::TypeRef::FLOAT64)
      callee_builder = Adamas::MIR::Builder.new(callee)
      callee_builder.ret(0_u32)

      caller = mod.create_function("call_uint_to_f64_arg", Adamas::MIR::TypeRef::FLOAT64)
      caller.add_param("x", Adamas::MIR::TypeRef::UINT32)
      caller_builder = Adamas::MIR::Builder.new(caller)
      call = caller_builder.call(callee.id, ([0_u32] of Adamas::MIR::ValueId), Adamas::MIR::TypeRef::FLOAT64)
      caller_builder.ret(call)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define double @call_uint_to_f64_arg\([^)]*\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!

      body.should contain("uitofp i32 %x to double")
      body.should_not contain("sitofp i32 %x to double")
    end

    it "uses fptoui for float64 argument when calling uint32 callee" do
      mod = Adamas::MIR::Module.new("test")

      callee = mod.create_function("takes_u32_arg", Adamas::MIR::TypeRef::UINT32)
      callee.add_param("x", Adamas::MIR::TypeRef::UINT32)
      callee_builder = Adamas::MIR::Builder.new(callee)
      callee_builder.ret(0_u32)

      caller = mod.create_function("call_f64_to_u32_arg", Adamas::MIR::TypeRef::UINT32)
      caller.add_param("x", Adamas::MIR::TypeRef::FLOAT64)
      caller_builder = Adamas::MIR::Builder.new(caller)
      call = caller_builder.extern_call("takes_u32_arg", ([0_u32] of Adamas::MIR::ValueId), Adamas::MIR::TypeRef::UINT32)
      caller_builder.ret(call)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define i32 @call_f64_to_u32_arg\([^)]*\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!

      body.should contain("fptoui double %x to i32")
      body.should_not contain("fptosi double %x to i32")
    end

    it "decodes a pointer-carried float64 argument by preserving its bit pattern" do
      mod = Adamas::MIR::Module.new("test")

      callee = mod.create_function("takes_f64_ptr_arg", Adamas::MIR::TypeRef::FLOAT64)
      callee.add_param("x", Adamas::MIR::TypeRef::FLOAT64)
      callee_builder = Adamas::MIR::Builder.new(callee)
      callee_builder.ret(0_u32)

      caller = mod.create_function("call_ptr_to_f64_arg", Adamas::MIR::TypeRef::FLOAT64)
      caller.add_param("p", Adamas::MIR::TypeRef::POINTER)
      caller_builder = Adamas::MIR::Builder.new(caller)
      call = caller_builder.call(callee.id, ([0_u32] of Adamas::MIR::ValueId), Adamas::MIR::TypeRef::FLOAT64)
      caller_builder.ret(call)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define double @call_ptr_to_f64_arg\([^)]*\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!

      body.should contain("ptrtoint ptr %p to i64")
      body.should match(/bitcast i64 %ptr_to_fp\.\d+\.bits64 to double/)
      body.should_not contain("uitofp")
      body.should_not contain("load double, ptr %p")
    end

    it "evaluates abstract Int#remainder(Int32) directly for scalar receivers" do
      mod = Adamas::MIR::Module.new("test")

      check = mod.create_function("Int#check_div_argument$Int32", Adamas::MIR::TypeRef::INT32)
      check.add_param("self", Adamas::MIR::TypeRef::POINTER)
      check.add_param("other", Adamas::MIR::TypeRef::INT32)
      check_builder = Adamas::MIR::Builder.new(check)
      zero = check_builder.const_int(0, Adamas::MIR::TypeRef::INT32)
      check_builder.ret(zero)

      callee = mod.create_function("Int#remainder$Int32", Adamas::MIR::TypeRef::INT32)
      callee.add_param("self", Adamas::MIR::TypeRef::POINTER)
      callee.add_param("other", Adamas::MIR::TypeRef::INT32)
      callee_builder = Adamas::MIR::Builder.new(callee)
      callee_builder.ret(1_u32)

      caller = mod.create_function("call_int_remainder", Adamas::MIR::TypeRef::INT32)
      caller.add_param("self", Adamas::MIR::TypeRef::INT32)
      caller.add_param("other", Adamas::MIR::TypeRef::INT32)
      caller_builder = Adamas::MIR::Builder.new(caller)
      call = caller_builder.call(callee.id, [0_u32, 1_u32], Adamas::MIR::TypeRef::INT32)
      caller_builder.ret(call)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define i32 @call_int_remainder\([^)]*\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!

      body.should contain("alloca i32")
      body.should contain("store i32 %self")
      body.should contain("call i32 @Int$Hcheck_div_argument$$Int32")
      body.should contain("srem i32 %self, %other")
      body.should_not contain("call i32 @Int$Hremainder$$Int32")
      body.should_not contain("inttoptr i64 %self")
    end

    it "evaluates bare Tuple#size directly for concrete tuple receivers" do
      mod = Adamas::MIR::Module.new("test")

      tuple_type = mod.type_registry.create_type(
        Adamas::MIR::TypeKind::Tuple,
        "Tuple(Float64)",
        8_u64,
        8_u32
      )
      float64_type = mod.type_registry.get(Adamas::MIR::TypeRef::FLOAT64)
      float64_type.should_not be_nil
      tuple_type.add_element_type(float64_type.not_nil!)
      tuple_ref = Adamas::MIR::TypeRef.new(tuple_type.id)

      callee = mod.create_function("Tuple#size", Adamas::MIR::TypeRef::INT32)
      callee.add_param("self", tuple_ref)
      callee_builder = Adamas::MIR::Builder.new(callee)
      zero = callee_builder.const_int(0, Adamas::MIR::TypeRef::INT32)
      callee_builder.ret(zero)

      caller = mod.create_function("call_tuple_size", Adamas::MIR::TypeRef::INT32)
      caller.add_param("self", tuple_ref)
      caller_builder = Adamas::MIR::Builder.new(caller)
      call = caller_builder.call(callee.id, [0_u32], Adamas::MIR::TypeRef::INT32)
      caller_builder.ret(call)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define i32 @call_tuple_size\([^)]*\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!

      body.should contain("add i32 0, 1")
      body.should_not contain("call i32 @Tuple$Hsize")
    end

    it "evaluates abstract Int#tdiv(Int32) directly for scalar receivers" do
      mod = Adamas::MIR::Module.new("test")

      check = mod.create_function("Int#check_div_argument$Int32", Adamas::MIR::TypeRef::INT32)
      check.add_param("self", Adamas::MIR::TypeRef::POINTER)
      check.add_param("other", Adamas::MIR::TypeRef::INT32)
      check_builder = Adamas::MIR::Builder.new(check)
      zero = check_builder.const_int(0, Adamas::MIR::TypeRef::INT32)
      check_builder.ret(zero)

      callee = mod.create_function("Int#tdiv$Int32", Adamas::MIR::TypeRef::POINTER)
      callee.add_param("self", Adamas::MIR::TypeRef::POINTER)
      callee.add_param("other", Adamas::MIR::TypeRef::INT32)
      callee_builder = Adamas::MIR::Builder.new(callee)
      callee_builder.ret(0_u32)

      caller = mod.create_function("call_int_tdiv", Adamas::MIR::TypeRef::POINTER)
      caller.add_param("self", Adamas::MIR::TypeRef::INT32)
      caller.add_param("other", Adamas::MIR::TypeRef::INT32)
      caller_builder = Adamas::MIR::Builder.new(caller)
      call = caller_builder.call(callee.id, [0_u32, 1_u32], Adamas::MIR::TypeRef::POINTER)
      caller_builder.ret(call)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define ptr @call_int_tdiv\([^)]*\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!

      body.should contain("alloca i32")
      body.should contain("store i32 %self")
      body.should contain("call i32 @Int$Hcheck_div_argument$$Int32")
      body.should contain("sdiv i32 %self, %other")
      body.should contain("%int_div_ret.")
      body.should contain("store i32 %int_div_res.")
      body.should_not contain("call ptr @Int$Htdiv$$Int32")
      body.should_not contain("inttoptr i64 %self")
    end

    it "dispatches abstract Int#to_s on scalar receivers to concrete integer implementations" do
      mod = Adamas::MIR::Module.new("test")

      concrete = mod.create_function("Int32#to_s", Adamas::MIR::TypeRef::POINTER)
      concrete.add_param("self", Adamas::MIR::TypeRef::INT32)
      concrete.add_param("base", Adamas::MIR::TypeRef::INT32)
      concrete.add_param("precision", Adamas::MIR::TypeRef::INT32)
      concrete.add_param("upcase", Adamas::MIR::TypeRef::BOOL)
      concrete_builder = Adamas::MIR::Builder.new(concrete)
      concrete_builder.ret(0_u32)

      callee = mod.create_function("Int#to_s$Int32_Int32_Bool", Adamas::MIR::TypeRef::POINTER)
      callee.add_param("self", Adamas::MIR::TypeRef::POINTER)
      callee.add_param("base", Adamas::MIR::TypeRef::INT32)
      callee.add_param("precision", Adamas::MIR::TypeRef::INT32)
      callee.add_param("upcase", Adamas::MIR::TypeRef::BOOL)
      callee_builder = Adamas::MIR::Builder.new(callee)
      callee_builder.ret(0_u32)

      caller = mod.create_function("call_abstract_int_to_s", Adamas::MIR::TypeRef::POINTER)
      caller.add_param("self", Adamas::MIR::TypeRef::INT32)
      caller.add_param("base", Adamas::MIR::TypeRef::INT32)
      caller.add_param("precision", Adamas::MIR::TypeRef::INT32)
      caller.add_param("upcase", Adamas::MIR::TypeRef::BOOL)
      caller_builder = Adamas::MIR::Builder.new(caller)
      call = caller_builder.call(callee.id, [0_u32, 1_u32, 2_u32, 3_u32], Adamas::MIR::TypeRef::POINTER)
      caller_builder.ret(call)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define ptr @call_abstract_int_to_s\([^)]*\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!

      body.should contain("call ptr @Int32$Hto_s(i32 %self, i32 %base, i32 %precision, i1 %upcase)")
      body.should_not contain("call ptr @Int$Hto_s$$Int32_Int32_Bool")
      body.should_not contain("inttoptr i64 %self")
      body.should_not contain("inttoptr i32 %self")
    end

    it "lowers abstract Int#to_s(IO, ...) on scalar receivers via concrete to_s plus String#to_s(IO)" do
      mod = Adamas::MIR::Module.new("test")

      concrete = mod.create_function("Int32#to_s", Adamas::MIR::TypeRef::POINTER)
      concrete.add_param("self", Adamas::MIR::TypeRef::INT32)
      concrete.add_param("base", Adamas::MIR::TypeRef::INT32)
      concrete.add_param("precision", Adamas::MIR::TypeRef::INT32)
      concrete.add_param("upcase", Adamas::MIR::TypeRef::BOOL)
      concrete_builder = Adamas::MIR::Builder.new(concrete)
      concrete_builder.ret(0_u32)

      io_append = mod.create_function("IO#<<$String", Adamas::MIR::TypeRef::POINTER)
      io_append.add_param("io", Adamas::MIR::TypeRef::POINTER)
      io_append.add_param("str", Adamas::MIR::TypeRef::POINTER)
      io_builder = Adamas::MIR::Builder.new(io_append)
      io_builder.ret(0_u32)

      callee = mod.create_function("Int#to_s$IO_Int32_Int32_Bool", Adamas::MIR::TypeRef::VOID)
      callee.add_param("self", Adamas::MIR::TypeRef::POINTER)
      callee.add_param("io", Adamas::MIR::TypeRef::POINTER)
      callee.add_param("base", Adamas::MIR::TypeRef::INT32)
      callee.add_param("precision", Adamas::MIR::TypeRef::INT32)
      callee.add_param("upcase", Adamas::MIR::TypeRef::BOOL)
      callee_builder = Adamas::MIR::Builder.new(callee)
      callee_builder.ret

      caller = mod.create_function("call_abstract_int_to_s_io", Adamas::MIR::TypeRef::VOID)
      caller.add_param("self", Adamas::MIR::TypeRef::INT32)
      caller.add_param("io", Adamas::MIR::TypeRef::POINTER)
      caller.add_param("base", Adamas::MIR::TypeRef::INT32)
      caller.add_param("precision", Adamas::MIR::TypeRef::INT32)
      caller.add_param("upcase", Adamas::MIR::TypeRef::BOOL)
      caller_builder = Adamas::MIR::Builder.new(caller)
      caller_builder.call(callee.id, [0_u32, 1_u32, 2_u32, 3_u32, 4_u32], Adamas::MIR::TypeRef::VOID)
      caller_builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define void @call_abstract_int_to_s_io\([^)]*\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!

      body.should contain("call ptr @Int32$Hto_s(i32 %self, i32 %base, i32 %precision, i1 %upcase)")
      body.should contain("call ptr @String$Hto_s$$IO(ptr %int_to_s_io.")
      body.should_not contain("call void @Int$Hto_s$$IO_Int32_Int32_Bool")
      body.should_not contain("inttoptr i64 %self")
      body.should_not contain("inttoptr i32 %self")
    end

    it "uses uitofp for uint128 argument when calling float64 callee" do
      mod = Adamas::MIR::Module.new("test")

      callee = mod.create_function("takes_f64_arg_u128", Adamas::MIR::TypeRef::FLOAT64)
      callee.add_param("x", Adamas::MIR::TypeRef::FLOAT64)
      callee_builder = Adamas::MIR::Builder.new(callee)
      callee_builder.ret(0_u32)

      caller = mod.create_function("call_uint128_to_f64_arg", Adamas::MIR::TypeRef::FLOAT64)
      caller.add_param("x", Adamas::MIR::TypeRef::UINT128)
      caller_builder = Adamas::MIR::Builder.new(caller)
      call = caller_builder.call(callee.id, ([0_u32] of Adamas::MIR::ValueId), Adamas::MIR::TypeRef::FLOAT64)
      caller_builder.ret(call)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define double @call_uint128_to_f64_arg\([^)]*\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!

      body.should contain("uitofp i128 %x to double")
      body.should_not contain("sitofp i128 %x to double")
    end

    it "uses align 4 for union payload load in union-to-float call coercion" do
      mod = Adamas::MIR::Module.new("test")

      union_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Union, "FloatOrNilArg", 16, 8)
      union_ref = Adamas::MIR::TypeRef.new(union_type.id)
      mod.register_union(
        union_ref,
        Adamas::MIR::UnionDescriptor.new(
          "FloatOrNilArg",
          [
            Adamas::MIR::UnionVariantDescriptor.new(
              type_id: Adamas::MIR::TypeRef::FLOAT64.id.to_i32,
              type_ref: Adamas::MIR::TypeRef::FLOAT64,
              full_name: "Float64",
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
      )

      callee = mod.create_function("takes_union_coerced_f64", Adamas::MIR::TypeRef::FLOAT64)
      callee.add_param("x", Adamas::MIR::TypeRef::FLOAT64)
      callee_builder = Adamas::MIR::Builder.new(callee)
      callee_builder.ret(0_u32)

      caller = mod.create_function("call_union_to_f64_arg", Adamas::MIR::TypeRef::FLOAT64)
      caller.add_param("u", union_ref)
      caller_builder = Adamas::MIR::Builder.new(caller)
      call = caller_builder.call(callee.id, ([0_u32] of Adamas::MIR::ValueId), Adamas::MIR::TypeRef::FLOAT64)
      caller_builder.ret(call)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define double @call_union_to_f64_arg\([^)]*\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!

      body.should match(/%union_to_fp\.\d+\.val = load double, ptr %union_to_fp\.\d+\.payload_ptr, align 4/)
    end

    it "uses a raw nullable pointer for Pointer | Nil with literal null and non-null phi inputs" do
      mod = Adamas::MIR::Module.new("phi_union_ptr")

      union_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Union, "PtrOrNil", 16, 8)
      union_ref = Adamas::MIR::TypeRef.new(union_type.id)
      mod.register_union(
        union_ref,
        Adamas::MIR::UnionDescriptor.new(
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
      )

      func = mod.create_function("phi_union_ptr", Adamas::MIR::TypeRef::INT32)
      builder = Adamas::MIR::Builder.new(func)

      entry = func.entry_block
      then_block = func.create_block
      else_block = func.create_block
      merge_block = func.create_block

      cond = builder.const_bool(true)
      builder.branch(cond, then_block, else_block)

      builder.current_block = then_block
      ptr_val = builder.alloc(Adamas::MIR::MemoryStrategy::Stack, Adamas::MIR::TypeRef::INT32, 4_u64, 4_u32)
      builder.jump(merge_block)

      builder.current_block = else_block
      nil_val = builder.const_nil
      builder.jump(merge_block)

      builder.current_block = merge_block
      phi = builder.phi(union_ref)
      phi.add_incoming(from: then_block, value: ptr_val)
      phi.add_incoming(from: else_block, value: nil_val)
      type_id = builder.emit(Adamas::MIR::UnionTypeIdGet.new(func.next_value_id, phi.id))
      builder.emit(Adamas::MIR::UnionIs.new(func.next_value_id, phi.id, 0, union_ref))
      builder.emit(
        Adamas::MIR::UnionIs.new(
          func.next_value_id,
          phi.id,
          Adamas::MIR::TypeRef::POINTER.id.to_i32,
          union_ref
        )
      )
      builder.ret(type_id)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define i32 @phi_union_ptr\(\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      phi_line = func_ir.not_nil!.lines.find { |line| line.includes?(" = phi ptr ") }
      phi_line.should_not be_nil
      phi_line.not_nil!.should contain("null")
      phi_line.not_nil!.should match(/\[%r\d+/)
      func_ir.not_nil!.should_not contain("%PtrOrNil.union")
      func_ir.not_nil!.should match(/\.is_null = icmp eq ptr %r\d+, null/)
      func_ir.not_nil!.should match(/select i1 %r\d+\.is_null, i32 0, i32 #{Adamas::MIR::TypeRef::POINTER.id}/)
      func_ir.not_nil!.should_not contain("safe_tid_ptr")
      func_ir.not_nil!.should_not contain("obj_tid_raw")
      func_ir.not_nil!.scan(/ = icmp eq ptr .* null/).size.should be >= 2
      func_ir.not_nil!.should match(/ = icmp ne ptr %r\d+, null/)
      func_ir.not_nil!.should match(/ret i32 %r\d+/)
    end

    it "uses object headers to dispatch A | B | Nil raw-pointer unions" do
      mod = Adamas::MIR::Module.new("header_union")
      a_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Reference, "HeaderA", 8, 8)
      b_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Reference, "HeaderB", 8, 8)
      a_ref = Adamas::MIR::TypeRef.new(a_type.id)
      b_ref = Adamas::MIR::TypeRef.new(b_type.id)

      union_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Union, "HeaderA | HeaderB | Nil", 16, 8)
      union_ref = Adamas::MIR::TypeRef.new(union_type.id)
      mod.register_union(
        union_ref,
        Adamas::MIR::UnionDescriptor.new(
          "HeaderA | HeaderB | Nil",
          [
            Adamas::MIR::UnionVariantDescriptor.new(
              type_id: a_ref.id.to_i32,
              type_ref: a_ref,
              full_name: "HeaderA",
              size: 8,
              alignment: 8,
              field_offsets: nil
            ),
            Adamas::MIR::UnionVariantDescriptor.new(
              type_id: b_ref.id.to_i32,
              type_ref: b_ref,
              full_name: "HeaderB",
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
      )

      func = mod.create_function("header_union_type_id", Adamas::MIR::TypeRef::INT32)
      func.add_param("value", union_ref)
      builder = Adamas::MIR::Builder.new(func)
      type_id = builder.emit(Adamas::MIR::UnionTypeIdGet.new(func.next_value_id, 0_u32))
      builder.emit(Adamas::MIR::UnionIs.new(func.next_value_id, 0_u32, 0, union_ref))
      builder.emit(Adamas::MIR::UnionIs.new(func.next_value_id, 0_u32, a_ref.id.to_i32, union_ref))
      builder.ret(type_id)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define i32 @header_union_type_id\(ptr %value\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!
      body.should contain("icmp eq ptr %value, null")
      body.should contain("safe_tid_ptr = select")
      body.should contain("obj_tid_raw = load i32")
      body.should match(/select i1 %r\d+\.is_null, i32 0, i32 %r\d+\.obj_tid_raw/)
      body.should match(/\.tid_match = icmp eq i32 %r\d+\.obj_tid, #{a_ref.id}/)
      body.scan(/ = icmp eq ptr %value, null/).size.should be >= 2
      body.should_not contain(".union")
      body.should match(/ret i32 %r\d+/)
    end

    it "keeps Pointer | A | Nil tagged because Pointer has no runtime type-id header" do
      mod = Adamas::MIR::Module.new("mixed_pointer_union")
      a_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Reference, "MixedA", 8, 8)
      a_ref = Adamas::MIR::TypeRef.new(a_type.id)
      union_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Union, "Pointer | MixedA | Nil", 16, 8)
      union_ref = Adamas::MIR::TypeRef.new(union_type.id)
      mod.register_union(
        union_ref,
        Adamas::MIR::UnionDescriptor.new(
          "Pointer | MixedA | Nil",
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
              type_id: a_ref.id.to_i32,
              type_ref: a_ref,
              full_name: "MixedA",
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
      )

      consumer = mod.create_function("mixed_pointer_union_consume", Adamas::MIR::TypeRef::INT32)
      consumer.add_param("value", union_ref)
      consumer_builder = Adamas::MIR::Builder.new(consumer)
      type_id = consumer_builder.emit(Adamas::MIR::UnionTypeIdGet.new(consumer.next_value_id, 0_u32))
      consumer_builder.ret(type_id)

      raw_caller = mod.create_function("mixed_pointer_union_from_raw", Adamas::MIR::TypeRef::INT32)
      raw_caller.add_param("value", Adamas::MIR::TypeRef::POINTER)
      raw_builder = Adamas::MIR::Builder.new(raw_caller)
      raw_result = raw_builder.call(consumer.id, [0_u32], Adamas::MIR::TypeRef::INT32)
      raw_builder.ret(raw_result)

      object_caller = mod.create_function("mixed_pointer_union_from_object", Adamas::MIR::TypeRef::INT32)
      object_caller.add_param("value", a_ref)
      object_builder = Adamas::MIR::Builder.new(object_caller)
      object_result = object_builder.call(consumer.id, [0_u32], Adamas::MIR::TypeRef::INT32)
      object_builder.ret(object_result)

      nil_caller = mod.create_function("mixed_pointer_union_from_nil", Adamas::MIR::TypeRef::INT32)
      nil_builder = Adamas::MIR::Builder.new(nil_caller)
      nil_value = nil_builder.const_nil
      nil_result = nil_builder.call(consumer.id, [nil_value], Adamas::MIR::TypeRef::INT32)
      nil_builder.ret(nil_result)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      body = output[/define i32 @mixed_pointer_union_consume\([^)]*\)\s*\{.*?\n\}/m].not_nil!
      body.should contain(".union_ptr = alloca %Pointer$_$OR$_MixedA$_$OR$_Nil.union")
      body.should contain(".type_id_ptr = getelementptr %Pointer$_$OR$_MixedA$_$OR$_Nil.union")
      body.should match(/ret i32 %r\d+/)
      body.should_not contain("safe_tid_ptr")
      body.should_not contain("obj_tid_raw")
      output.should contain("define i32 @mixed_pointer_union_from_raw")
      output.should contain("define i32 @mixed_pointer_union_from_object")
      output.should contain("define i32 @mixed_pointer_union_from_nil")
      output.scan("call i32 @mixed_pointer_union_consume(%Pointer$_$OR$_MixedA$_$OR$_Nil.union").size.should eq(3)
      raw_body = output[/define i32 @mixed_pointer_union_from_raw\([^)]*\)\s*\{.*?\n\}/m].not_nil!
      object_body = output[/define i32 @mixed_pointer_union_from_object\([^)]*\)\s*\{.*?\n\}/m].not_nil!
      nil_body = output[/define i32 @mixed_pointer_union_from_nil\([^)]*\)\s*\{.*?\n\}/m].not_nil!
      raw_body.should contain("store i32 #{Adamas::MIR::TypeRef::POINTER.id}")
      object_body.should contain("store i32 #{a_ref.id}")
      nil_body.should contain("store i32 0")
    end

    it "classifies distinct raw pointer variants from the sidecar and keeps them tagged" do
      mod = Adamas::MIR::Module.new("multi_pointer_union")
      int32_pointer_type = mod.type_registry.create_type(
        Adamas::MIR::TypeKind::Pointer,
        "Pointer(Int32)",
        8,
        8
      )
      int32_pointer_type.set_element_type(mod.type_registry.get(Adamas::MIR::TypeRef::INT32).not_nil!)
      int32_pointer_ref = Adamas::MIR::TypeRef.new(int32_pointer_type.id)
      uint8_pointer_type = mod.type_registry.create_type(
        Adamas::MIR::TypeKind::Pointer,
        "Pointer(UInt8)",
        8,
        8
      )
      uint8_pointer_type.set_element_type(mod.type_registry.get(Adamas::MIR::TypeRef::UINT8).not_nil!)
      uint8_pointer_ref = Adamas::MIR::TypeRef.new(uint8_pointer_type.id)
      int32_pointer_ref.should_not eq(uint8_pointer_ref)
      int32_pointer_type.element_type.not_nil!.id.should eq(Adamas::MIR::TypeRef::INT32.id)
      uint8_pointer_type.element_type.not_nil!.id.should eq(Adamas::MIR::TypeRef::UINT8.id)
      union_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Union, "Pointer(Int32) | Pointer(UInt8)", 16, 8)
      union_ref = Adamas::MIR::TypeRef.new(union_type.id)
      descriptor = Adamas::MIR::UnionDescriptor.new(
        "Pointer(Int32) | Pointer(UInt8)",
        [
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: int32_pointer_ref.id.to_i32,
            type_ref: int32_pointer_ref,
            full_name: "Pointer(Int32)",
            size: 8,
            alignment: 8,
            field_offsets: nil
          ),
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: uint8_pointer_ref.id.to_i32,
            type_ref: uint8_pointer_ref,
            full_name: "Pointer(UInt8)",
            size: 8,
            alignment: 8,
            field_offsets: nil
          ),
        ],
        16,
        8
      )
      mod.register_union(union_ref, descriptor)

      # Deliberately poison only the legacy Hash value. Both Module lookup and
      # LLVM classification must continue to observe the sidecar descriptor.
      mod.union_descriptors[union_ref] = Adamas::MIR::UnionDescriptor.new(
        "Pointer | Nil",
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
      mod.union_descriptors[union_ref].name.should eq("Pointer | Nil")
      mod.get_union_descriptor(union_ref).not_nil!.name.should eq("Pointer(Int32) | Pointer(UInt8)")

      consumer = mod.create_function("multi_pointer_union_consume", Adamas::MIR::TypeRef::INT32)
      consumer.add_param("value", union_ref)
      consumer_builder = Adamas::MIR::Builder.new(consumer)
      type_id = consumer_builder.emit(Adamas::MIR::UnionTypeIdGet.new(consumer.next_value_id, 0_u32))
      consumer_builder.ret(type_id)

      left_caller = mod.create_function("multi_pointer_union_from_i32", Adamas::MIR::TypeRef::INT32)
      left_caller.add_param("value", int32_pointer_ref)
      left_builder = Adamas::MIR::Builder.new(left_caller)
      left_result = left_builder.call(consumer.id, [0_u32], Adamas::MIR::TypeRef::INT32)
      left_builder.ret(left_result)

      right_caller = mod.create_function("multi_pointer_union_from_u8", Adamas::MIR::TypeRef::INT32)
      right_caller.add_param("value", uint8_pointer_ref)
      right_builder = Adamas::MIR::Builder.new(right_caller)
      right_result = right_builder.call(consumer.id, [0_u32], Adamas::MIR::TypeRef::INT32)
      right_builder.ret(right_result)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      body = output[/define i32 @multi_pointer_union_consume\([^)]*\)\s*\{.*?\n\}/m].not_nil!
      body.should contain(".union_ptr = alloca %Pointer$LInt32$R$_$OR$_Pointer$LUInt8$R.union")
      body.should contain(".type_id_ptr = getelementptr %Pointer$LInt32$R$_$OR$_Pointer$LUInt8$R.union")
      body.should_not contain("safe_tid_ptr")
      body.should_not contain("obj_tid_raw")
      body.should match(/ret i32 %r\d+/)
      output.scan("call i32 @multi_pointer_union_consume(%Pointer$LInt32$R$_$OR$_Pointer$LUInt8$R.union").size.should eq(2)
      left_body = output[/define i32 @multi_pointer_union_from_i32\([^)]*\)\s*\{.*?\n\}/m].not_nil!
      right_body = output[/define i32 @multi_pointer_union_from_u8\([^)]*\)\s*\{.*?\n\}/m].not_nil!
      left_body.should contain("store i32 #{int32_pointer_ref.id}")
      right_body.should contain("store i32 #{uint8_pointer_ref.id}")
    end

    it "selects cast-wrap variant ids from the sidecar when the legacy Hash is poisoned" do
      mod = Adamas::MIR::Module.new("poisoned_tagged_union")
      union_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Union, "Int32 | Float64 | Nil", 16, 8)
      union_ref = Adamas::MIR::TypeRef.new(union_type.id)
      int32_variant_id = Adamas::MIR::TypeRef::INT32.id.to_i32
      mod.register_union(
        union_ref,
        Adamas::MIR::UnionDescriptor.new(
          "Int32 | Float64 | Nil",
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
              type_id: Adamas::MIR::TypeRef::FLOAT64.id.to_i32,
              type_ref: Adamas::MIR::TypeRef::FLOAT64,
              full_name: "Float64",
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
      )

      # If backend code reads this legacy Hash value, the cast-wrap path stamps
      # Float64 instead of Int32. The sidecar retains the registered descriptor.
      mod.union_descriptors[union_ref] = Adamas::MIR::UnionDescriptor.new(
        "PoisonedFloat64OrNil",
        [
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: Adamas::MIR::TypeRef::FLOAT64.id.to_i32,
            type_ref: Adamas::MIR::TypeRef::FLOAT64,
            full_name: "Float64",
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
      mod.union_descriptors[union_ref].variants.any? { |variant| variant.type_ref == Adamas::MIR::TypeRef::INT32 }.should be_false
      mod.get_union_descriptor(union_ref).not_nil!.variants.any? { |variant| variant.type_ref == Adamas::MIR::TypeRef::INT32 }.should be_true

      func = mod.create_function("poisoned_tagged_wrap", Adamas::MIR::TypeRef::INT32)
      func.add_param("value", Adamas::MIR::TypeRef::INT32)
      builder = Adamas::MIR::Builder.new(func)
      builder.cast(Adamas::MIR::CastKind::Bitcast, 0_u32, union_ref)
      builder.ret(0_u32)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate
      body = output[/define i32 @poisoned_tagged_wrap\(i32 %value\)\s*\{.*?\n\}/m].not_nil!

      body.scan("store i32 #{int32_variant_id}").size.should eq(1)
      body.should_not contain("store i32 #{Adamas::MIR::TypeRef::FLOAT64.id}")
      body.should match(/ret i32 %value/)
    end

    it "unwraps an Int32 payload from a tagged union parameter" do
      mod = Adamas::MIR::Module.new("tagged_union_unwrap")
      union_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Union, "Int32 | Float64", 16, 8)
      union_ref = Adamas::MIR::TypeRef.new(union_type.id)
      int32_variant_id = Adamas::MIR::TypeRef::INT32.id.to_i32
      mod.register_union(
        union_ref,
        Adamas::MIR::UnionDescriptor.new(
          "Int32 | Float64",
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
              type_id: Adamas::MIR::TypeRef::FLOAT64.id.to_i32,
              type_ref: Adamas::MIR::TypeRef::FLOAT64,
              full_name: "Float64",
              size: 8,
              alignment: 8,
              field_offsets: nil
            ),
          ],
          16,
          8
        )
      )

      func = mod.create_function("tagged_union_unwrap", Adamas::MIR::TypeRef::INT32)
      func.add_param("value", union_ref)
      builder = Adamas::MIR::Builder.new(func)
      unwrapped = builder.emit(
        Adamas::MIR::UnionUnwrap.new(
          func.next_value_id,
          Adamas::MIR::TypeRef::INT32,
          0_u32,
          int32_variant_id
        )
      )
      builder.ret(unwrapped)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate
      body = output[/define i32 @tagged_union_unwrap\([^)]*\)\s*\{.*?\n\}/m].not_nil!

      body.should contain(".payload_ptr = getelementptr %Int32$_$OR$_Float64.union")
      body.scan(/load i32, ptr %r\d+\.payload_ptr, align 4/).size.should eq(1)
      body.should match(/ret i32 %r\d+/)
    end

    it "emits align 4 for UInt64 union payload store/load" do
      mod = Adamas::MIR::Module.new("union_align_u64")

      union_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Union, "U64OrNilAlign", 16, 8)
      union_ref = Adamas::MIR::TypeRef.new(union_type.id)
      mod.register_union(
        union_ref,
        Adamas::MIR::UnionDescriptor.new(
          "U64OrNilAlign",
          [
            Adamas::MIR::UnionVariantDescriptor.new(
              type_id: Adamas::MIR::TypeRef::UINT64.id.to_i32,
              type_ref: Adamas::MIR::TypeRef::UINT64,
              full_name: "UInt64",
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
      )

      func = mod.create_function("union_align_payload_u64", Adamas::MIR::TypeRef::UINT64)
      func.add_param("x", Adamas::MIR::TypeRef::UINT64)
      builder = Adamas::MIR::Builder.new(func)
      uint64_variant_id = Adamas::MIR::TypeRef::UINT64.id.to_i32
      wrapped = builder.union_wrap(0_u32, uint64_variant_id, union_ref)
      unwrapped = builder.emit(Adamas::MIR::UnionUnwrap.new(func.next_value_id, Adamas::MIR::TypeRef::UINT64, wrapped, uint64_variant_id))
      builder.ret(unwrapped)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define i64 @union_align_payload_u64\(i64 %x\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      body = func_ir.not_nil!
      body.should match(/store i64 %x, ptr %.*payload_ptr, align 4/)
      body.should match(/load i64, ptr %.*payload_ptr, align 4/)
    end

    it "generates RC increment and decrement" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("rc_test", Adamas::MIR::TypeRef::VOID)
      func.add_param("ptr", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      builder.rc_inc(0_u32)
      builder.rc_dec(0_u32)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      # Parameters use their name directly
      output.should contain("call void @__adamas_rc_inc(ptr %ptr)")
      output.should contain("call void @__adamas_rc_dec(ptr %ptr, ptr null)")
    end

    it "routes atomic RC increment through the guarded atomic helper" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("atomic_rc_inc", Adamas::MIR::TypeRef::VOID)
      func.add_param("ptr", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      builder.rc_inc(0_u32, atomic: true)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define void @atomic_rc_inc\(ptr %ptr\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      func_ir.not_nil!.should contain("call void @__adamas_rc_inc_atomic(ptr %ptr)")

      helper_ir = output[/define void @__adamas_rc_inc_atomic\(ptr %ptr\)\s*\{.*?\n\}/m]
      helper_ir.should_not be_nil
      helper = helper_ir.not_nil!
      {% if flag?(:darwin) %}
        helper.should contain("%is_null = icmp eq ptr %ptr, null")
        helper.should contain("%raw = getelementptr i8, ptr %ptr, i64 -8")
        helper.should contain("%raw_size = call i64 @malloc_size(ptr %raw)")
        helper.should contain("%has_header = icmp ne i64 %raw_size, 0")
        helper.should contain("%is_static = icmp uge i64 %old, 4611686018427387904")
        helper.should contain("atomicrmw add ptr %raw, i64 1 seq_cst")
      {% else %}
        helper.should contain("ret void")
        helper.should_not contain("malloc_size")
        helper.should_not contain("atomicrmw")
      {% end %}
    end

    it "routes atomic RC decrement through the guarded conditional-free helper" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("atomic_rc_dec", Adamas::MIR::TypeRef::VOID)
      func.add_param("ptr", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      builder.rc_dec(0_u32, atomic: true)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      func_ir = output[/define void @atomic_rc_dec\(ptr %ptr\)\s*\{.*?\n\}/m]
      func_ir.should_not be_nil
      func_ir.not_nil!.should contain("call void @__adamas_rc_dec_atomic(ptr %ptr, ptr null)")

      helper_ir = output[/define void @__adamas_rc_dec_atomic\(ptr %ptr, ptr %destructor\)\s*\{.*?\n\}/m]
      helper_ir.should_not be_nil
      helper = helper_ir.not_nil!
      {% if flag?(:darwin) %}
        helper.should contain("%is_null = icmp eq ptr %ptr, null")
        helper.should contain("%raw = getelementptr i8, ptr %ptr, i64 -8")
        helper.should contain("%raw_size = call i64 @malloc_size(ptr %raw)")
        helper.should contain("%has_header = icmp ne i64 %raw_size, 0")
        helper.should contain("%is_static = icmp uge i64 %peek, 4611686018427387904")
        helper.should contain("atomicrmw sub ptr %raw, i64 1 acq_rel")
        helper.should contain("icmp eq i64 %old, 1")
        helper.should contain("label %do_free")
        helper.should contain("%has_dtor = icmp ne ptr %destructor, null")
        helper.should contain("call void %destructor(ptr %ptr)")
        helper.should contain("call void @free(ptr %raw)")
      {% else %}
        helper.should contain("ret void")
        helper.should_not contain("malloc_size")
        helper.should_not contain("atomicrmw")
      {% end %}
    end

    it "generates TSan instrumentation for load/store when enabled" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("tsan_test", Adamas::MIR::TypeRef::VOID)
      func.add_param("ptr", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      loaded = builder.load(0_u32, Adamas::MIR::TypeRef::INT32)
      builder.store(0_u32, loaded)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      gen.emit_tsan = true
      output = gen.generate

      # Should declare TSan functions
      output.should contain("declare void @__tsan_read4(ptr)")
      output.should contain("declare void @__tsan_write4(ptr)")
      output.should contain("declare void @__tsan_func_entry(ptr)")
      output.should contain("declare void @__tsan_func_exit()")

      # Should instrument load and store
      output.should contain("call void @__tsan_read4(ptr %ptr)")
      output.should contain("call void @__tsan_write4(ptr %ptr)")

      # Should have function entry/exit
      output.should contain("call void @__tsan_func_entry")
      output.should contain("call void @__tsan_func_exit()")
    end

    it "does not generate TSan instrumentation when disabled" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("no_tsan", Adamas::MIR::TypeRef::VOID)
      func.add_param("ptr", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      loaded = builder.load(0_u32, Adamas::MIR::TypeRef::INT32)
      builder.store(0_u32, loaded)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      gen.emit_tsan = false
      output = gen.generate

      # Should NOT have TSan instrumentation
      output.should_not contain("@__tsan_read")
      output.should_not contain("@__tsan_write")
      output.should_not contain("@__tsan_func_entry")
    end

    it "adds TSan synchronization only when atomic RC instrumentation is enabled" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("tsan_atomic_rc", Adamas::MIR::TypeRef::VOID)
      func.add_param("ptr", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      builder.rc_inc(0_u32, atomic: true)
      builder.rc_dec(0_u32, atomic: true)
      builder.ret

      tsan_gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      tsan_gen.emit_type_metadata = false
      tsan_gen.emit_tsan = true
      tsan_output = tsan_gen.generate

      plain_gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      plain_gen.emit_type_metadata = false
      plain_gen.emit_tsan = false
      plain_output = plain_gen.generate

      tsan_func = tsan_output[/define void @tsan_atomic_rc\(ptr %ptr\)\s*\{.*?\n\}/m].not_nil!
      plain_func = plain_output[/define void @tsan_atomic_rc\(ptr %ptr\)\s*\{.*?\n\}/m].not_nil!

      tsan_func.scan("call void @__tsan_release(ptr %ptr)").size.should eq(2)
      tsan_func.scan("call void @__tsan_acquire(ptr %ptr)").size.should eq(2)
      tsan_func.should contain("call void @__adamas_rc_inc_atomic(ptr %ptr)")
      tsan_func.should contain("call void @__adamas_rc_dec_atomic(ptr %ptr, ptr null)")
      plain_func.should_not contain("@__tsan_release")
      plain_func.should_not contain("@__tsan_acquire")
    end

    it "generates binary operations" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("binop_test", Adamas::MIR::TypeRef::INT32)
      func.add_param("a", Adamas::MIR::TypeRef::INT32)
      func.add_param("b", Adamas::MIR::TypeRef::INT32)

      builder = Adamas::MIR::Builder.new(func)
      sum = builder.add(0_u32, 1_u32, Adamas::MIR::TypeRef::INT32)
      diff = builder.sub(0_u32, 1_u32, Adamas::MIR::TypeRef::INT32)
      prod = builder.mul(0_u32, 1_u32, Adamas::MIR::TypeRef::INT32)
      builder.ret(prod)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("add i32")
      output.should contain("sub i32")
      output.should contain("mul i32")
    end

    it "generates conditional branch" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("branch_test", Adamas::MIR::TypeRef::INT32)
      func.add_param("cond", Adamas::MIR::TypeRef::BOOL)
      func.add_param("a", Adamas::MIR::TypeRef::INT32)
      func.add_param("b", Adamas::MIR::TypeRef::INT32)

      then_block = func.create_block
      else_block = func.create_block
      exit_block = func.create_block

      builder = Adamas::MIR::Builder.new(func)
      builder.branch(0_u32, then_block, else_block)

      builder.current_block = then_block
      builder.jump(exit_block)

      builder.current_block = else_block
      builder.jump(exit_block)

      builder.current_block = exit_block
      builder.ret(1_u32)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("br i1")
      output.should contain("br label")
    end
  end

  describe "type metadata generation" do
    it "generates __crystal_type_count global" do
      mod = Adamas::MIR::Module.new("test")

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = true
      output = gen.generate

      output.should contain("@__crystal_type_count = constant i32")
    end

    it "generates __crystal_type_info array" do
      mod = Adamas::MIR::Module.new("test")

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = true
      output = gen.generate

      output.should contain("@__crystal_type_info = constant")
      output.should contain("%__crystal_type_info_entry = type { i32, i32, i32, i32, i32, i32, i32, i32 }")
    end

    it "generates __crystal_type_strings table" do
      mod = Adamas::MIR::Module.new("test")

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = true
      output = gen.generate

      output.should contain("@__crystal_type_strings = constant")
    end

    it "includes primitive types in metadata" do
      mod = Adamas::MIR::Module.new("test")

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = true
      output = gen.generate

      # Should have entries for all primitive types
      # TypeRegistry registers 19 primitive types (including Pointer)
      output.should contain("@__crystal_type_count = constant i32 19")
    end

    it "generates field info for struct types" do
      mod = Adamas::MIR::Module.new("test")

      # Create a struct type with fields
      struct_type = mod.type_registry.create_type(
        Adamas::MIR::TypeKind::Struct,
        "Point",
        8_u64,
        4_u32
      )
      struct_type.add_field("x", Adamas::MIR::TypeRef::INT32, 0_u32)
      struct_type.add_field("y", Adamas::MIR::TypeRef::INT32, 4_u32)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = true
      output = gen.generate

      output.should contain("@__crystal_field_info = constant")
      output.should contain("%__crystal_field_info_entry = type { i32, i32, i32, i32 }")
    end

    it "emits large homogeneous tuples as DW_TAG_array_type with a DISubrange" do
      mod = Adamas::MIR::Module.new("test")
      tuple_type = mod.type_registry.create_type(
        Adamas::MIR::TypeKind::Tuple,
        "HugeUInt64Tuple",
        1301_u64 * 8_u64,
        8_u32
      )
      uint64_type = mod.type_registry.get(Adamas::MIR::TypeRef::UINT64)
      uint64_type.should_not be_nil
      1301.times do
        tuple_type.add_element_type(uint64_type.not_nil!)
      end

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      gen.emit_debug_info = true
      output = gen.generate

      output.should contain("!DICompositeType(tag: DW_TAG_array_type, baseType: !1300000011")
      output.should contain("!DISubrange(count: 1301)")
      output.should_not contain("name: \"[1300]\"")
    end

    it "deduplicates colliding lexical block metadata ids" do
      mod = Adamas::MIR::Module.new("test")
      ctx = Adamas::MIR::DwarfDebugContext.new(mod, Adamas::MIR::LLVMTypeMapper.new(mod.type_registry))
      assigned = {} of Int32 => String
      first_key = "lexblock:300001524:3"
      second_key = "lexblock:300002527:9"

      raw_first = ctx.__test_stable_metadata_id(
        first_key,
        Adamas::MIR::DwarfDebugContext::LEXICAL_BLOCK_ID_BASE,
        Adamas::MIR::DwarfDebugContext::LEXICAL_BLOCK_ID_SPAN
      )
      raw_second = ctx.__test_stable_metadata_id(
        second_key,
        Adamas::MIR::DwarfDebugContext::LEXICAL_BLOCK_ID_BASE,
        Adamas::MIR::DwarfDebugContext::LEXICAL_BLOCK_ID_SPAN
      )
      raw_first.should eq(raw_second)

      unique_first = ctx.__test_unique_stable_metadata_id(
        assigned,
        first_key,
        Adamas::MIR::DwarfDebugContext::LEXICAL_BLOCK_ID_BASE,
        Adamas::MIR::DwarfDebugContext::LEXICAL_BLOCK_ID_SPAN
      )
      unique_second = ctx.__test_unique_stable_metadata_id(
        assigned,
        second_key,
        Adamas::MIR::DwarfDebugContext::LEXICAL_BLOCK_ID_BASE,
        Adamas::MIR::DwarfDebugContext::LEXICAL_BLOCK_ID_SPAN
      )

      unique_first.should_not eq(unique_second)
      assigned.size.should eq(2)
    end
  end

  describe "synchronization primitives" do
    it "generates atomic load with memory ordering" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("atomic_load_test", Adamas::MIR::TypeRef::INT64)
      func.add_param("ptr", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      result = builder.atomic_load(0_u32, Adamas::MIR::TypeRef::INT64, Adamas::MIR::MemoryOrdering::Acquire)
      builder.ret(result)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("load atomic i64")
      output.should contain("acquire")
    end

    it "generates atomic store with memory ordering" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("atomic_store_test", Adamas::MIR::TypeRef::VOID)
      func.add_param("ptr", Adamas::MIR::TypeRef::POINTER)
      func.add_param("val", Adamas::MIR::TypeRef::INT64)

      builder = Adamas::MIR::Builder.new(func)
      builder.atomic_store(0_u32, 1_u32, Adamas::MIR::MemoryOrdering::Release)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("store atomic")
      output.should contain("release")
    end

    it "generates atomic compare-and-swap" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("atomic_cas_test", Adamas::MIR::TypeRef::INT64)
      func.add_param("ptr", Adamas::MIR::TypeRef::POINTER)
      func.add_param("expected", Adamas::MIR::TypeRef::INT64)
      func.add_param("desired", Adamas::MIR::TypeRef::INT64)

      builder = Adamas::MIR::Builder.new(func)
      result = builder.atomic_cas(0_u32, 1_u32, 2_u32, Adamas::MIR::TypeRef::INT64)
      builder.ret(result)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("cmpxchg")
      output.should contain("seq_cst")
      output.should contain("extractvalue")
    end

    it "generates atomic read-modify-write operations" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("atomic_rmw_test", Adamas::MIR::TypeRef::INT64)
      func.add_param("ptr", Adamas::MIR::TypeRef::POINTER)
      func.add_param("val", Adamas::MIR::TypeRef::INT64)

      builder = Adamas::MIR::Builder.new(func)
      result = builder.atomic_rmw(Adamas::MIR::AtomicRMWOp::Add, 0_u32, 1_u32, Adamas::MIR::TypeRef::INT64)
      builder.ret(result)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("atomicrmw add")
      output.should contain("seq_cst")
    end

    it "generates memory fence" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("fence_test", Adamas::MIR::TypeRef::VOID)

      builder = Adamas::MIR::Builder.new(func)
      builder.fence(Adamas::MIR::MemoryOrdering::AcqRel)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("fence acq_rel")
    end

    it "generates mutex lock/unlock calls" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("mutex_test", Adamas::MIR::TypeRef::VOID)
      func.add_param("mutex", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      builder.mutex_lock(0_u32)
      builder.mutex_unlock(0_u32)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("call void @__adamas_mutex_lock")
      output.should contain("call void @__adamas_mutex_unlock")
    end

    it "generates mutex trylock call" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("trylock_test", Adamas::MIR::TypeRef::BOOL)
      func.add_param("mutex", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      result = builder.mutex_trylock(0_u32)
      builder.ret(result)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("call i1 @__adamas_mutex_trylock")
    end

    it "generates channel send/receive/close calls" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("channel_test", Adamas::MIR::TypeRef::POINTER)
      func.add_param("channel", Adamas::MIR::TypeRef::POINTER)
      func.add_param("data", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      builder.channel_send(0_u32, 1_u32)
      result = builder.channel_receive(0_u32, Adamas::MIR::TypeRef::POINTER)
      builder.channel_close(0_u32)
      builder.ret(result)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("call void @__adamas_channel_send")
      output.should contain("call ptr @__adamas_channel_receive")
      output.should contain("call void @__adamas_channel_close")
    end

    it "generates TSan annotations for mutex operations" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("mutex_tsan_test", Adamas::MIR::TypeRef::VOID)
      func.add_param("mutex", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      builder.mutex_lock(0_u32)
      builder.mutex_unlock(0_u32)
      builder.ret

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      gen.emit_tsan = true
      output = gen.generate

      output.should contain("@__tsan_acquire")
      output.should contain("@__tsan_release")
    end

    it "generates TSan annotations for channel operations" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("channel_tsan_test", Adamas::MIR::TypeRef::POINTER)
      func.add_param("channel", Adamas::MIR::TypeRef::POINTER)
      func.add_param("data", Adamas::MIR::TypeRef::POINTER)

      builder = Adamas::MIR::Builder.new(func)
      builder.channel_send(0_u32, 1_u32)
      result = builder.channel_receive(0_u32, Adamas::MIR::TypeRef::POINTER)
      builder.ret(result)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      gen.emit_tsan = true
      output = gen.generate

      # Send releases, receive acquires
      output.should contain("@__tsan_release")
      output.should contain("@__tsan_acquire")
    end

    it "keeps widened primitive override results consistent with the declared function return type" do
      mod = Adamas::MIR::Module.new("test")
      func = mod.create_function("UInt32#+$UInt64", Adamas::MIR::TypeRef::UINT32)
      func.add_param("self", Adamas::MIR::TypeRef::UINT32)
      func.add_param("other", Adamas::MIR::TypeRef::UINT64)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("define i32 @UInt32$H$ADD$$UInt64(i32 %self, i64 %other)")
      output.should contain("; UInt32#ADD primitive override")
      output.should contain("%result = add i64")
      output.should contain("%result_ret = trunc i64 %result to i32")
      output.should contain("ret i32 %result_ret")
      output.should_not contain("ret i64 %result")
    end

    it "inlines zeroed Crystal::Hasher allocation in key_hash overrides" do
      mod = Adamas::MIR::Module.new("test")
      mod.type_registry.create_type(
        Adamas::MIR::TypeKind::Struct,
        "Crystal::Hasher",
        16_u64,
        8_u32
      )

      func = mod.create_function("Hash(Int32, Int32)#key_hash$Int32", Adamas::MIR::TypeRef::INT32)
      func.add_param("self", Adamas::MIR::TypeRef::POINTER)
      func.add_param("key", Adamas::MIR::TypeRef::INT32)

      builder = Adamas::MIR::Builder.new(func)
      zero = builder.const_int(0_i64, Adamas::MIR::TypeRef::INT32)
      builder.ret(zero)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("define i32 @Hash$LInt32$C$_Int32$R$Hkey_hash$$Int32")
      output.should contain("call ptr @__adamas_malloc64(i64 24)")
      output.should contain("call void @llvm.memset.p0.i64(ptr %hasher, i8 0, i64 16, i1 false)")
      output.should_not contain("call ptr @Crystal$CCHasher$Dnew(i64 0, i64 0)")
      output.should_not contain("call i64 @Crystal$CCHasher$Hresult(ptr %hasher2)")
    end

    it "delegates tuple key_hash overrides to generic Tuple#hash with a live hasher" do
      mod = Adamas::MIR::Module.new("test")
      mod.type_registry.create_type(
        Adamas::MIR::TypeKind::Struct,
        "Crystal::Hasher",
        16_u64,
        8_u32
      )

      tuple_type = mod.type_registry.create_type(
        Adamas::MIR::TypeKind::Tuple,
        "Tuple(Float64)",
        8_u64,
        8_u32
      )
      float64_type = mod.type_registry.get(Adamas::MIR::TypeRef::FLOAT64)
      float64_type.should_not be_nil
      tuple_type.add_element_type(float64_type.not_nil!)
      tuple_ref = Adamas::MIR::TypeRef.new(tuple_type.id)

      tuple_hash = mod.create_function("Tuple#hash", Adamas::MIR::TypeRef::POINTER)
      tuple_hash.add_param("self", tuple_ref)
      tuple_hash.add_param("hasher", Adamas::MIR::TypeRef::POINTER)
      tuple_hash_builder = Adamas::MIR::Builder.new(tuple_hash)
      tuple_hash_builder.ret(1_u32)

      func = mod.create_function("Hash(Tuple(Float64), Nil)#key_hash$Tuple(Float64)", Adamas::MIR::TypeRef::INT32)
      func.add_param("self", Adamas::MIR::TypeRef::POINTER)
      func.add_param("key", tuple_ref)

      builder = Adamas::MIR::Builder.new(func)
      zero = builder.const_int(0_i64, Adamas::MIR::TypeRef::INT32)
      builder.ret(zero)

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      output.should contain("define i32 @Hash$LTuple$LFloat64$R$C$_Nil$R$Hkey_hash$$Tuple$LFloat64$R")
      output.should contain("call ptr @Tuple$Hhash(ptr %key, ptr %hasher)")
      output.should_not contain("call ptr @Tuple$Hhash(ptr %key, ptr null)")
    end

    it "does not delegate a concrete heterogeneous tuple key to a bare generic Tuple#hash" do
      mod = Adamas::MIR::Module.new("test")
      registry = mod.type_registry
      registry.create_type(
        Adamas::MIR::TypeKind::Struct,
        "Crystal::Hasher",
        16_u64,
        8_u32
      )

      # The key has a concrete heterogeneous layout, but the only hash body
      # available below is for the bare Tuple carrier.  Those receiver ABIs
      # are not interchangeable just because both lower to ptr.
      tuple_type = registry.create_type(
        Adamas::MIR::TypeKind::Tuple,
        "Tuple(String, UInt64, UInt64, Int32)",
        32_u64,
        8_u32
      )
      string_type = registry.get(Adamas::MIR::TypeRef::STRING)
      uint64_type = registry.get(Adamas::MIR::TypeRef::UINT64)
      int32_type = registry.get(Adamas::MIR::TypeRef::INT32)
      {string_type, uint64_type, int32_type}.each(&.should_not be_nil)
      tuple_type.add_element_type(string_type.not_nil!)
      tuple_type.add_element_type(uint64_type.not_nil!)
      tuple_type.add_element_type(uint64_type.not_nil!)
      tuple_type.add_element_type(int32_type.not_nil!)
      tuple_ref = Adamas::MIR::TypeRef.new(tuple_type.id)

      # Make the concrete String hash target available to the layout-aware
      # fallback.  The body is intentionally trivial; this example verifies
      # that the tuple emitter passes the element and its live hasher to it.
      string_hash = mod.create_function("String#hash$Crystal::Hasher", Adamas::MIR::TypeRef::POINTER)
      string_hash.add_param("self", Adamas::MIR::TypeRef::STRING)
      string_hash.add_param("hasher", Adamas::MIR::TypeRef::POINTER)
      Adamas::MIR::Builder.new(string_hash).ret(0_u32)

      bare_tuple = registry.create_type(
        Adamas::MIR::TypeKind::Struct,
        "Tuple",
        0_u64,
        8_u32
      )
      bare_tuple_ref = Adamas::MIR::TypeRef.new(bare_tuple.id)
      tuple_hash = mod.create_function("Tuple#hash", Adamas::MIR::TypeRef::POINTER)
      tuple_hash.add_param("self", bare_tuple_ref)
      tuple_hash.add_param("hasher", Adamas::MIR::TypeRef::POINTER)
      Adamas::MIR::Builder.new(tuple_hash).ret(1_u32)

      wrong_base_hash = mod.create_function(
        "Tuple#hash$Crystal::Hasher",
        Adamas::MIR::TypeRef::POINTER
      )
      wrong_base_hash.add_param("self", bare_tuple_ref)
      wrong_base_hash.add_param("hasher", Adamas::MIR::TypeRef::POINTER)
      Adamas::MIR::Builder.new(wrong_base_hash).ret(1_u32)

      wrong_exact_hash = mod.create_function(
        "Tuple(String, UInt64, UInt64, Int32)#hash$Crystal::Hasher",
        Adamas::MIR::TypeRef::POINTER
      )
      wrong_exact_hash.add_param("self", bare_tuple_ref)
      wrong_exact_hash.add_param("hasher", Adamas::MIR::TypeRef::POINTER)
      Adamas::MIR::Builder.new(wrong_exact_hash).ret(1_u32)

      key_hash_name = "Hash(Tuple(String, UInt64, UInt64, Int32), Nil)#key_hash$Tuple(String, UInt64, UInt64, Int32)"
      func = mod.create_function(key_hash_name, Adamas::MIR::TypeRef::INT32)
      func.add_param("self", Adamas::MIR::TypeRef::POINTER)
      func.add_param("key", tuple_ref)
      builder = Adamas::MIR::Builder.new(func)
      builder.ret(builder.const_int(0_i64, Adamas::MIR::TypeRef::INT32))

      gen = Adamas::MIR::LLVMIRGenerator.new(mod)
      gen.emit_type_metadata = false
      output = gen.generate

      mapper = Adamas::MIR::LLVMTypeMapper.new(registry)
      mangled = mapper.mangle_name(key_hash_name)
      body = output[/define i32 @#{Regex.escape(mangled)}\([^)]*\) \{.*?\n\}/m]
      body.should_not be_nil
      body = body.not_nil!

      # A concrete heterogeneous tuple must be read using its byte layout;
      # struct-level GEP would silently apply the wrong element stride.
      body.should contain("%tuple.elem0.ptr = getelementptr i8, ptr %key, i64 0")
      body.should contain("%tuple.elem0 = load ptr, ptr %tuple.elem0.ptr")
      body.should contain("%tuple.elem1.ptr = getelementptr i8, ptr %key, i64 8")
      body.should contain("%tuple.elem1 = load i64, ptr %tuple.elem1.ptr")
      body.should contain("%tuple.elem2.ptr = getelementptr i8, ptr %key, i64 16")
      body.should contain("%tuple.elem2 = load i64, ptr %tuple.elem2.ptr")
      body.should contain("%tuple.elem3.ptr = getelementptr i8, ptr %key, i64 24")
      body.should contain("%tuple.elem3 = load i32, ptr %tuple.elem3.ptr")

      # String receives the live hasher through its concrete hash method;
      # scalar elements are mixed directly as UInt64 values.
      body.should contain("call ptr @String$Hhash$$Crystal$CCHasher(ptr %tuple.elem0, ptr %hasher)")
      permute = "call ptr @Crystal$CCHasher$Hpermute$$UInt64"
      body.lines.count { |line| line.includes?(permute) }.should eq(3)
      body.lines.count { |line| line.includes?("urem i64") }.should eq(2)

      # Preserve the ABI-safety guard against both generic and concrete-named
      # targets whose actual self TypeRef is the bare Tuple carrier.
      body.should_not contain("call ptr @Tuple$Hhash")
      body.should_not contain(
        "call ptr @Tuple$LString$C$_UInt64$C$_UInt64$C$_Int32$R$Hhash$$Crystal$CCHasher"
      )

      # Hash result is i32, with Crystal's zero sentinel mapped to UInt32::MAX.
      body.should contain("%hash32 = trunc i64 %hash64 to i32")
      body.should contain("%is_zero = icmp eq i32 %hash32, 0")
      body.should contain("ret i32 -1")
      body.should contain("ret i32 %hash32")
    end
  end
end

describe Adamas::MIR::TypeRegistry do
  it "pre-registers primitive types" do
    registry = Adamas::MIR::TypeRegistry.new

    int32 = registry.get(Adamas::MIR::TypeRef::INT32)
    int32.should_not be_nil
    int32.not_nil!.name.should eq("Int32")
    int32.not_nil!.kind.should eq(Adamas::MIR::TypeKind::Int32)
    int32.not_nil!.size.should eq(4)
  end

  it "creates custom types" do
    registry = Adamas::MIR::TypeRegistry.new

    point = registry.create_type(Adamas::MIR::TypeKind::Struct, "Point", 8_u64, 4_u32)
    point.id.should be >= 100 # Custom types start at ID 100
    point.name.should eq("Point")
    point.kind.should eq(Adamas::MIR::TypeKind::Struct)
  end

  it "looks up types by name" do
    registry = Adamas::MIR::TypeRegistry.new

    int32 = registry.get_by_name("Int32")
    int32.should_not be_nil
    int32.not_nil!.id.should eq(Adamas::MIR::TypeRef::INT32.id)
  end
end

describe Adamas::MIR::Type do
  it "supports adding fields" do
    type = Adamas::MIR::Type.new(100_u32, Adamas::MIR::TypeKind::Struct, "Point", 8_u64, 4_u32)

    type.add_field("x", Adamas::MIR::TypeRef::INT32, 0_u32)
    type.add_field("y", Adamas::MIR::TypeRef::INT32, 4_u32)

    type.fields.should_not be_nil
    type.fields.not_nil!.size.should eq(2)
    type.fields.not_nil![0].name.should eq("x")
    type.fields.not_nil![1].name.should eq("y")
  end

  it "detects value types" do
    struct_type = Adamas::MIR::Type.new(100_u32, Adamas::MIR::TypeKind::Struct, "Point", 8_u64, 4_u32)
    class_type = Adamas::MIR::Type.new(101_u32, Adamas::MIR::TypeKind::Reference, "Object", 8_u64, 8_u32)

    struct_type.is_value_type?.should be_true
    class_type.is_value_type?.should be_false
  end
end
