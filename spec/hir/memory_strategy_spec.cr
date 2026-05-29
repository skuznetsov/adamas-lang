require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/memory_strategy"

# Helper to create a simple function for testing
private def create_function(name : String = "test") : {Adamas::HIR::Module, Adamas::HIR::Function}
  mod = Adamas::HIR::Module.new
  func = mod.create_function(name, Adamas::HIR::TypeRef::VOID)
  {mod, func}
end

describe Adamas::HIR::MemoryStrategyAssigner do
  # ═══════════════════════════════════════════════════════════════════════════
  # STACK ALLOCATION
  # ═══════════════════════════════════════════════════════════════════════════

  describe "stack allocation" do
    it "assigns Stack to small non-escaping allocations" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Small allocation that doesn't escape
      alloc = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef::INT32)
      entry.add(alloc)

      # Use but don't return
      entry.terminator = Adamas::HIR::Return.new(nil)

      result = func.assign_memory_strategies
      result[alloc.id].should eq(Adamas::HIR::MemoryStrategy::Stack)
    end

    it "assigns Stack to primitive types" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Various primitive allocations
      int32 = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef::INT32)
      entry.add(int32)

      int64 = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef::INT64)
      entry.add(int64)

      float64 = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef::FLOAT64)
      entry.add(float64)

      entry.terminator = Adamas::HIR::Return.new(nil)

      result = func.assign_memory_strategies

      result[int32.id].should eq(Adamas::HIR::MemoryStrategy::Stack)
      result[int64.id].should eq(Adamas::HIR::MemoryStrategy::Stack)
      result[float64.id].should eq(Adamas::HIR::MemoryStrategy::Stack)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ARC ALLOCATION
  # ═══════════════════════════════════════════════════════════════════════════

  describe "ARC allocation" do
    it "assigns ARC to returned allocations" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Allocation that escapes via return
      alloc = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(alloc)

      entry.terminator = Adamas::HIR::Return.new(alloc.id)

      result = func.assign_memory_strategies
      result[alloc.id].should eq(Adamas::HIR::MemoryStrategy::ARC)
    end

    it "assigns ARC to closure-captured allocations" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Allocation captured by closure
      alloc = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(alloc)

      closure_block = func.create_block(func.scopes[0].id)
      captures = [Adamas::HIR::CapturedVar.new(alloc.id, "x", by_reference: true)]
      closure = Adamas::HIR::MakeClosure.new(func.next_value_id, Adamas::HIR::TypeRef.new(50_u32), closure_block, captures)
      entry.add(closure)

      entry.terminator = Adamas::HIR::Return.new(nil)

      result = func.assign_memory_strategies
      result[alloc.id].should eq(Adamas::HIR::MemoryStrategy::ARC)
    end

    it "assigns ARC to container-added allocations" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Container
      container = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(container)

      # Item added to container
      item = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(101_u32))
      entry.add(item)

      # container << item
      call = Adamas::HIR::Call.new(func.next_value_id, Adamas::HIR::TypeRef::VOID, container.id, "<<", [item.id])
      entry.add(call)

      entry.terminator = Adamas::HIR::Return.new(nil)

      result = func.assign_memory_strategies
      # Item escapes into container → ARC
      result[item.id].should eq(Adamas::HIR::MemoryStrategy::ARC)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ATOMIC ARC ALLOCATION
  # ═══════════════════════════════════════════════════════════════════════════

  describe "AtomicARC allocation" do
    it "assigns AtomicARC to thread-shared allocations" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Allocation passed to spawn
      data = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(data)

      spawn_call = Adamas::HIR::Call.new(func.next_value_id, Adamas::HIR::TypeRef::VOID, nil, "spawn", [data.id])
      entry.add(spawn_call)

      entry.terminator = Adamas::HIR::Return.new(nil)

      result = func.assign_memory_strategies
      result[data.id].should eq(Adamas::HIR::MemoryStrategy::AtomicARC)
    end

    it "assigns AtomicARC to class variable values" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Allocation stored in class var
      data = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(data)

      class_var_set = Adamas::HIR::ClassVarSet.new(func.next_value_id, Adamas::HIR::TypeRef::VOID, "Cache", "value", data.id)
      entry.add(class_var_set)

      entry.terminator = Adamas::HIR::Return.new(nil)

      result = func.assign_memory_strategies
      # Class vars are thread-shared → AtomicARC
      result[data.id].should eq(Adamas::HIR::MemoryStrategy::AtomicARC)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GC ALLOCATION
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GC allocation" do
    it "assigns GC to FFI-exposed allocations" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Allocation exposed to FFI
      data = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(data)

      # to_unsafe call
      ffi_call = Adamas::HIR::Call.new(func.next_value_id, Adamas::HIR::TypeRef::VOID, data.id, "to_unsafe", [] of Adamas::HIR::ValueId)
      entry.add(ffi_call)

      entry.terminator = Adamas::HIR::Return.new(nil)

      result = func.assign_memory_strategies
      result[data.id].should eq(Adamas::HIR::MemoryStrategy::GC)
    end

    it "assigns GC to cyclic types" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Allocation of cyclic type (pre-mark as cyclic for test)
      node = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      node.taints |= Adamas::HIR::Taint::Cyclic  # Pre-mark
      entry.add(node)

      entry.terminator = Adamas::HIR::Return.new(nil)

      result = func.assign_memory_strategies
      result[node.id].should eq(Adamas::HIR::MemoryStrategy::GC)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONFIGURATION MODES
  # ═══════════════════════════════════════════════════════════════════════════

  describe "configuration modes" do
    it "conservative mode prefers GC" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Large allocation that doesn't escape
      large_alloc = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(large_alloc)

      entry.terminator = Adamas::HIR::Return.new(nil)

      # Conservative mode
      result = func.assign_memory_strategies(Adamas::HIR::MemoryConfig.conservative)
      result[large_alloc.id].should eq(Adamas::HIR::MemoryStrategy::GC)
    end

    it "aggressive mode still uses GC for FFI-exposed allocations" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      data = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(data)

      ffi_call = Adamas::HIR::Call.new(func.next_value_id, Adamas::HIR::TypeRef::VOID, data.id, "to_unsafe", [] of Adamas::HIR::ValueId)
      entry.add(ffi_call)

      entry.terminator = Adamas::HIR::Return.new(nil)

      result = func.assign_memory_strategies(Adamas::HIR::MemoryConfig.aggressive)
      result[data.id].should eq(Adamas::HIR::MemoryStrategy::GC)
    end

    it "aggressive mode prefers ARC" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Allocation that escapes
      alloc = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(alloc)

      entry.terminator = Adamas::HIR::Return.new(alloc.id)

      # Aggressive mode
      result = func.assign_memory_strategies(Adamas::HIR::MemoryConfig.aggressive)
      result[alloc.id].should eq(Adamas::HIR::MemoryStrategy::ARC)
    end

    it "balanced mode uses decision tree" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Small non-escaping → Stack
      small = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef::INT32)
      entry.add(small)

      # Escaping → ARC
      escaping = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(escaping)

      entry.terminator = Adamas::HIR::Return.new(escaping.id)

      result = func.assign_memory_strategies(Adamas::HIR::MemoryConfig.balanced)
      result[small.id].should eq(Adamas::HIR::MemoryStrategy::Stack)
      result[escaping.id].should eq(Adamas::HIR::MemoryStrategy::ARC)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # STATISTICS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "statistics" do
    it "tracks allocation counts by strategy" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Stack allocation
      stack1 = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef::INT32)
      entry.add(stack1)

      stack2 = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef::INT64)
      entry.add(stack2)

      # ARC allocation (escapes)
      arc = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(arc)

      entry.terminator = Adamas::HIR::Return.new(arc.id)

      result = func.assign_memory_strategies

      result.stats.stack_count.should eq(2)
      result.stats.arc_count.should eq(1)
      result.stats.total.should eq(3)
    end

    it "provides helper methods" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Create an escaping allocation
      alloc = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(alloc)

      entry.terminator = Adamas::HIR::Return.new(alloc.id)

      assigner = Adamas::HIR::MemoryStrategyAssigner.new(func)
      assigner.assign

      assigner.uses_arc?.should be_true
      assigner.uses_gc?.should be_false
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INTEGRATION
  # ═══════════════════════════════════════════════════════════════════════════

  describe "end-to-end integration" do
    it "handles complex function with mixed strategies" do
      mod, func = create_function

      entry = func.get_block(func.entry_block)

      # Local counter (Stack)
      counter = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef::INT32)
      entry.add(counter)

      # Result object (ARC - returned)
      result_obj = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(100_u32))
      entry.add(result_obj)

      # Shared data (AtomicARC - passed to spawn)
      shared = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(101_u32))
      entry.add(shared)

      spawn_call = Adamas::HIR::Call.new(func.next_value_id, Adamas::HIR::TypeRef::VOID, nil, "spawn", [shared.id])
      entry.add(spawn_call)

      # FFI data (GC)
      ffi_data = Adamas::HIR::Allocate.new(func.next_value_id, Adamas::HIR::TypeRef.new(102_u32))
      entry.add(ffi_data)

      ffi_call = Adamas::HIR::Call.new(func.next_value_id, Adamas::HIR::TypeRef::VOID, ffi_data.id, "to_unsafe", [] of Adamas::HIR::ValueId)
      entry.add(ffi_call)

      entry.terminator = Adamas::HIR::Return.new(result_obj.id)

      result = func.assign_memory_strategies

      result[counter.id].should eq(Adamas::HIR::MemoryStrategy::Stack)
      result[result_obj.id].should eq(Adamas::HIR::MemoryStrategy::ARC)
      result[shared.id].should eq(Adamas::HIR::MemoryStrategy::AtomicARC)
      result[ffi_data.id].should eq(Adamas::HIR::MemoryStrategy::GC)

      result.stats.stack_count.should eq(1)
      result.stats.arc_count.should eq(1)
      result.stats.atomic_arc_count.should eq(1)
      result.stats.gc_count.should eq(1)
    end
  end
end
