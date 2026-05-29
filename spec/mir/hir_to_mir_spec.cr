require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/escape_analysis"
require "../../src/compiler/hir/taint_analysis"
require "../../src/compiler/hir/memory_strategy"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"

describe Adamas::MIR::HIRToMIRLowering do
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

    it "inserts RC operations for ARC allocations" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("arc_alloc", Adamas::HIR::TypeRef.new(100_u32))
      block = hir_func.get_block(hir_func.entry_block)

      alloc = Adamas::HIR::Allocate.new(hir_func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
      block.add(alloc)
      block.terminator = Adamas::HIR::Return.new(alloc.id)

      mir_mod = hir_mod.lower_to_mir

      mir_block = mir_mod.functions[0].get_block(mir_mod.functions[0].entry_block)
      rc_inc = mir_block.instructions.find { |i| i.is_a?(Adamas::MIR::RCIncrement) }
      rc_inc.should_not be_nil
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
            type_id: 0,
            type_ref: Adamas::MIR::TypeRef::POINTER,
            full_name: "Pointer",
            size: 8,
            alignment: 8,
            field_offsets: nil
          ),
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 1,
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
      lowering.register_union_types({mir_union_ref => mir_union_desc})
      mir_mod = lowering.lower

      mir_func = mir_mod.functions.find { |f| f.name == "phi_union_ptr" }
      mir_func.should_not be_nil
      mir_func = mir_func.not_nil!

      phi_inst = mir_func.blocks.flat_map(&.instructions).find { |i| i.is_a?(Adamas::MIR::Phi) }
      phi_inst.should_not be_nil
      phi_inst = phi_inst.not_nil!.as(Adamas::MIR::Phi)
      phi_inst.type.should eq(mir_union_ref)

      phi_inst.incoming.each do |(block_id, value_id)|
        block = mir_func.get_block(block_id)
        wrap = block.instructions.find { |i| i.is_a?(Adamas::MIR::UnionWrap) && i.id == value_id }
        wrap.should_not be_nil
        wrap.not_nil!.as(Adamas::MIR::UnionWrap).type.should eq(mir_union_ref)
      end
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

      wrap = Adamas::HIR::UnionWrap.new(hir_func.next_value_id, hir_union_ref, ptr_val.id, 0)
      block.add(wrap)

      unwrap = Adamas::HIR::UnionUnwrap.new(hir_func.next_value_id, hir_union_ref, wrap.id, 0)
      block.add(unwrap)
      block.terminator = Adamas::HIR::Return.new(unwrap.id)

      mir_union_ref = Adamas::MIR::TypeRef.new(hir_union_ref.id + 20_u32)
      mir_union_desc = Adamas::MIR::UnionDescriptor.new(
        "PtrOrNil",
        [
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 0,
            type_ref: Adamas::MIR::TypeRef::POINTER,
            full_name: "Pointer",
            size: 8,
            alignment: 8,
            field_offsets: nil
          ),
          Adamas::MIR::UnionVariantDescriptor.new(
            type_id: 1,
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
      lowering.register_union_types({mir_union_ref => mir_union_desc})
      mir_mod = lowering.lower

      mir_func = mir_mod.functions.find { |f| f.name == "union_unwrap_ptr" }
      mir_func.should_not be_nil
      mir_func = mir_func.not_nil!

      unwrap_inst = mir_func.blocks.flat_map(&.instructions).find { |i| i.is_a?(Adamas::MIR::UnionUnwrap) }
      unwrap_inst.should_not be_nil
      unwrap_inst = unwrap_inst.not_nil!.as(Adamas::MIR::UnionUnwrap)
      unwrap_inst.type.should eq(Adamas::MIR::TypeRef::POINTER)
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
