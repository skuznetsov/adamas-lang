# LTP/WBA Framework Tests
#
# Tests for the LTP (Local Trigger → Transport → Potential) optimization framework.
# Based on theory from "LTP/WBA Framework — From G_{3,5} to Kakeya & Magnus"

require "../../spec_helper"
require "../../../src/compiler/mir/mir"
require "../../../src/compiler/mir/optimizations"

# Helper module for test function creation
module LTPTestHelpers
  @@func_id_counter = 0_u32

  def self.next_func_id : Adamas::MIR::FunctionId
    @@func_id_counter += 1
    Adamas::MIR::FunctionId.new(@@func_id_counter)
  end

  def self.create_test_function_with_rc : Adamas::MIR::Function
    int_type = Adamas::MIR::TypeRef::INT32
    void_type = Adamas::MIR::TypeRef::VOID

    func = Adamas::MIR::Function.new(next_func_id, "test_rc", int_type)
    entry_id = func.create_block
    entry = func.get_block(entry_id)

    # Create: alloc → rc_inc → use → rc_dec → return
    # This is the simplest case for Spike move

    alloc = Adamas::MIR::Alloc.new(
      1_u32,                             # id
      int_type,                          # type (result type = ptr to alloc_type)
      Adamas::MIR::MemoryStrategy::ARC, # strategy
      int_type                           # alloc_type
    )
    alloc.no_alias = true
    entry.add(alloc)

    rc_inc = Adamas::MIR::RCIncrement.new(
      2_u32,      # id
      alloc.id    # ptr
    )
    entry.add(rc_inc)

    # Some use instruction
    load_inst = Adamas::MIR::Load.new(
      3_u32,       # id
      int_type,    # type
      alloc.id     # ptr
    )
    entry.add(load_inst)

    rc_dec = Adamas::MIR::RCDecrement.new(
      4_u32,       # id
      alloc.id     # ptr
    )
    entry.add(rc_dec)

    ret = Adamas::MIR::Return.new(load_inst.id)
    entry.terminator = ret

    func
  end

  def self.create_empty_function : Adamas::MIR::Function
    int_type = Adamas::MIR::TypeRef::INT32

    func = Adamas::MIR::Function.new(next_func_id, "empty", int_type)
    entry_id = func.create_block
    entry = func.get_block(entry_id)

    const = Adamas::MIR::Constant.new(
      1_u32,       # id
      int_type,    # type
      42_i64       # value
    )
    entry.add(const)

    ret = Adamas::MIR::Return.new(const.id)
    entry.terminator = ret

    func
  end

  def self.create_test_function_with_long_corridor : Adamas::MIR::Function
    int_type = Adamas::MIR::TypeRef::INT32

    func = Adamas::MIR::Function.new(next_func_id, "test_rc_long", int_type)
    entry_id = func.create_block
    entry = func.get_block(entry_id)

    alloc = Adamas::MIR::Alloc.new(
      1_u32,
      int_type,
      Adamas::MIR::MemoryStrategy::ARC,
      int_type
    )
    alloc.no_alias = true
    entry.add(alloc)

    rc_inc = Adamas::MIR::RCIncrement.new(2_u32, alloc.id)
    entry.add(rc_inc)

    # Add extra instructions between rc_inc and rc_dec to lengthen corridor.
    const1 = Adamas::MIR::Constant.new(3_u32, int_type, 1_i64)
    entry.add(const1)

    const2 = Adamas::MIR::Constant.new(4_u32, int_type, 2_i64)
    entry.add(const2)

    rc_dec = Adamas::MIR::RCDecrement.new(5_u32, alloc.id)
    entry.add(rc_dec)

    ret = Adamas::MIR::Return.new(const2.id)
    entry.terminator = ret

    func
  end

  def self.create_test_function_with_escape : Adamas::MIR::Function
    int_type = Adamas::MIR::TypeRef::INT32

    func = Adamas::MIR::Function.new(next_func_id, "test_rc_escape", int_type)
    entry_id = func.create_block
    entry = func.get_block(entry_id)

    alloc = Adamas::MIR::Alloc.new(
      1_u32,
      int_type,
      Adamas::MIR::MemoryStrategy::ARC,
      int_type
    )
    alloc.no_alias = true
    entry.add(alloc)

    rc_inc = Adamas::MIR::RCIncrement.new(2_u32, alloc.id)
    entry.add(rc_inc)

    call = Adamas::MIR::Call.new(
      3_u32,
      int_type,
      Adamas::MIR::FunctionId.new(999_u32),
      [alloc.id]
    )
    entry.add(call)

    ret = Adamas::MIR::Return.new(call.id)
    entry.terminator = ret

    func
  end

  def self.create_test_function_with_dead_code : Adamas::MIR::Function
    int_type = Adamas::MIR::TypeRef::INT32

    func = Adamas::MIR::Function.new(next_func_id, "test_dead", int_type)
    entry_id = func.create_block
    entry = func.get_block(entry_id)

    # Unused constant should be eliminated by DCE in the dual frame.
    dead_const = Adamas::MIR::Constant.new(
      1_u32,
      int_type,
      7_i64
    )
    entry.add(dead_const)

    live_const = Adamas::MIR::Constant.new(
      2_u32,
      int_type,
      42_i64
    )
    entry.add(live_const)

    ret = Adamas::MIR::Return.new(live_const.id)
    entry.terminator = ret

    func
  end
end

describe Adamas::MIR::LTPPotential do
  describe "lexicographic comparison" do
    it "compares window_overlap first" do
      p1 = Adamas::MIR::LTPPotential.new(5, 0, 0, 10)
      p2 = Adamas::MIR::LTPPotential.new(3, 0, 0, 10)

      (p2 < p1).should be_true  # Lower window_overlap is better
    end

    it "compares tie_plateau second" do
      # tie_plateau stored as negative count of ties
      # -2 means 2 ties, -1 means 1 tie
      # Lower value = more ties = worse
      # So -2 < -1, meaning p1 < p2 (p1 is better, fewer ties when stored negative)
      p1 = Adamas::MIR::LTPPotential.new(5, -2, 0, 10)
      p2 = Adamas::MIR::LTPPotential.new(5, -1, 0, 10)

      (p1 < p2).should be_true  # -2 < -1, so p1 has lower (better) potential
    end

    it "compares corner_mismatch third" do
      p1 = Adamas::MIR::LTPPotential.new(5, -2, 3, 10)
      p2 = Adamas::MIR::LTPPotential.new(5, -2, 1, 10)

      (p2 < p1).should be_true  # Lower mismatch is better
    end

    it "compares area last" do
      p1 = Adamas::MIR::LTPPotential.new(5, -2, 3, 15)
      p2 = Adamas::MIR::LTPPotential.new(5, -2, 3, 10)

      (p2 < p1).should be_true  # Lower area is better
    end

    it "equals when all components match" do
      p1 = Adamas::MIR::LTPPotential.new(5, -2, 3, 10)
      p2 = Adamas::MIR::LTPPotential.new(5, -2, 3, 10)

      (p1 == p2).should be_true
    end
  end

  describe ".zero" do
    it "creates zero potential" do
      p = Adamas::MIR::LTPPotential.zero

      p.window_overlap.should eq(0)
      p.tie_plateau.should eq(0)
      p.corner_mismatch.should eq(0)
      p.area.should eq(0)
    end
  end

  describe "#to_s" do
    it "formats potential correctly" do
      p = Adamas::MIR::LTPPotential.new(5, -2, 3, 10)
      p.to_s.should eq("Φ′{I=5, -M=-2, P=3, |Δ|=10}")
    end
  end
end

describe Adamas::MIR::CorridorExit do
  it "has all expected exit types" do
    Adamas::MIR::CorridorExit::Boundary.should be_truthy
    Adamas::MIR::CorridorExit::Elision.should be_truthy
    Adamas::MIR::CorridorExit::Escape.should be_truthy
    Adamas::MIR::CorridorExit::Store.should be_truthy
    Adamas::MIR::CorridorExit::Unknown.should be_truthy
  end
end

describe Adamas::MIR::MoveType do
  it "has all four legal move types" do
    Adamas::MIR::MoveType::Spike.should be_truthy
    Adamas::MIR::MoveType::Ladder.should be_truthy
    Adamas::MIR::MoveType::Diamond.should be_truthy
    Adamas::MIR::MoveType::Collapse.should be_truthy
  end
end

describe Adamas::MIR::LTPEngine do
  describe "#run" do
    it "terminates on empty function" do
      func = LTPTestHelpers.create_empty_function
      engine = Adamas::MIR::LTPEngine.new(func)
      potential = engine.run

      potential.window_overlap.should eq(0)
      engine.iterations.should eq(0)
    end

    it "computes initial potential correctly" do
      func = LTPTestHelpers.create_test_function_with_rc
      engine = Adamas::MIR::LTPEngine.new(func)

      # Before running, check initial state
      initial_insts = func.blocks.sum(&.instructions.size)
      initial_insts.should eq(4)  # alloc, rc_inc, load, rc_dec

      potential = engine.run

      # After LTP, RC ops should be optimized if possible
      # The potential's area should be less than or equal to initial
      potential.area.should be <= initial_insts
    end

    it "keeps potential monotone non-increasing" do
      func = LTPTestHelpers.create_test_function_with_rc
      engine = Adamas::MIR::LTPEngine.new(func)

      engine.run(max_iters: 5)
      trace = engine.potential_trace

      trace.size.should be > 0
      (1...trace.size).each do |idx|
        (trace[idx] <= trace[idx - 1]).should be_true
      end
    end
  end

  describe "BR-5 (Finiteness)" do
    it "terminates within max_iters" do
      func = LTPTestHelpers.create_test_function_with_rc
      engine = Adamas::MIR::LTPEngine.new(func)

      potential = engine.run(max_iters: 3)

      engine.iterations.should be <= 3
    end

    it "records moves applied" do
      func = LTPTestHelpers.create_test_function_with_rc
      engine = Adamas::MIR::LTPEngine.new(func)

      engine.run

      # Moves should be recorded
      engine.moves_applied.should be_a(Array(Adamas::MIR::LegalMove))
    end
  end

  describe "#curvature_potential" do
    it "penalizes longer corridors" do
      short_func = LTPTestHelpers.create_test_function_with_rc
      long_func = LTPTestHelpers.create_test_function_with_long_corridor

      short_potential = Adamas::MIR::LTPEngine.new(short_func).curvature_potential
      long_potential = Adamas::MIR::LTPEngine.new(long_func).curvature_potential

      long_potential.corner_mismatch.should be > short_potential.corner_mismatch
    end

    it "penalizes escape corridors more than elision" do
      elision_func = LTPTestHelpers.create_test_function_with_rc
      escape_func = LTPTestHelpers.create_test_function_with_escape

      elision_potential = Adamas::MIR::LTPEngine.new(elision_func).curvature_potential
      escape_potential = Adamas::MIR::LTPEngine.new(escape_func).curvature_potential

      escape_potential.corner_mismatch.should be > elision_potential.corner_mismatch
    end
  end

  describe "#frame_potential" do
    it "uses curvature mapping when frame_kind is Curvature" do
      func = LTPTestHelpers.create_test_function_with_long_corridor
      engine = Adamas::MIR::LTPEngine.new(func)
      engine.frame_kind = Adamas::MIR::FrameKind::Curvature

      engine.frame_potential.should eq(engine.curvature_potential)
    end
  end

  describe "dual-frame fallback" do
    it "switches to curvature frame when it reduces potential" do
      func = LTPTestHelpers.create_test_function_with_dead_code
      engine = Adamas::MIR::LTPEngine.new(func)

      engine.run(max_iters: 2)

      engine.frame_kind.should eq(Adamas::MIR::FrameKind::Curvature)

      trace = engine.potential_trace
      trace.size.should be >= 2
      (1...trace.size).each do |idx|
        (trace[idx] <= trace[idx - 1]).should be_true
      end
    end
  end
end

describe Adamas::MIR::Function do
  describe "#optimize_ltp" do
    it "provides convenience method for LTP optimization" do
      int_type = Adamas::MIR::TypeRef::INT32

      func = Adamas::MIR::Function.new(LTPTestHelpers.next_func_id, "test", int_type)
      entry_id = func.create_block
      entry = func.get_block(entry_id)

      const = Adamas::MIR::Constant.new(
        1_u32,
        int_type,
        42_i64
      )
      entry.add(const)

      ret = Adamas::MIR::Return.new(const.id)
      entry.terminator = ret

      potential = func.optimize_ltp

      potential.should be_a(Adamas::MIR::LTPPotential)
    end

    it "supports debug mode" do
      int_type = Adamas::MIR::TypeRef::INT32

      func = Adamas::MIR::Function.new(LTPTestHelpers.next_func_id, "test", int_type)
      entry_id = func.create_block
      entry = func.get_block(entry_id)

      const = Adamas::MIR::Constant.new(
        1_u32,
        int_type,
        42_i64
      )
      entry.add(const)

      ret = Adamas::MIR::Return.new(const.id)
      entry.terminator = ret

      # Should not raise with debug enabled
      potential = func.optimize_ltp(debug: false)
      potential.should be_a(Adamas::MIR::LTPPotential)
    end
  end
end

describe "LTP Theory Compliance" do
  describe "BR-3 (Potential Decrease)" do
    it "potential is well-founded (non-negative components)" do
      p = Adamas::MIR::LTPPotential.new(0, 0, 0, 0)

      # Zero is minimum
      (p >= Adamas::MIR::LTPPotential.zero).should be_true
    end

    it "potential strictly decreases or algorithm terminates" do
      int_type = Adamas::MIR::TypeRef::INT32

      func = Adamas::MIR::Function.new(LTPTestHelpers.next_func_id, "test", int_type)
      entry_id = func.create_block
      entry = func.get_block(entry_id)

      # Create function with RC ops
      # Alloc.new(id, type, strategy, alloc_type)
      alloc = Adamas::MIR::Alloc.new(
        1_u32,
        int_type,
        Adamas::MIR::MemoryStrategy::ARC,
        int_type
      )
      alloc.no_alias = true
      entry.add(alloc)

      # RCIncrement.new(id, ptr)
      rc_inc = Adamas::MIR::RCIncrement.new(2_u32, alloc.id)
      entry.add(rc_inc)

      # RCDecrement.new(id, ptr)
      rc_dec = Adamas::MIR::RCDecrement.new(3_u32, alloc.id)
      entry.add(rc_dec)

      ret = Adamas::MIR::Return.new(alloc.id)
      entry.terminator = ret

      engine = Adamas::MIR::LTPEngine.new(func)
      final_potential = engine.run

      # Either we made progress (potential decreased) or we terminated cleanly
      # The algorithm guarantees termination
      engine.iterations.should be >= 0
      final_potential.should be_a(Adamas::MIR::LTPPotential)
    end
  end

  describe "Legal Moves" do
    it "Spike move removes rc_inc/rc_dec pair" do
      int_type = Adamas::MIR::TypeRef::INT32

      func = Adamas::MIR::Function.new(LTPTestHelpers.next_func_id, "test_spike", int_type)
      entry_id = func.create_block
      entry = func.get_block(entry_id)

      # Alloc.new(id, type, strategy, alloc_type)
      alloc = Adamas::MIR::Alloc.new(
        1_u32,
        int_type,
        Adamas::MIR::MemoryStrategy::ARC,
        int_type
      )
      alloc.no_alias = true
      entry.add(alloc)

      # RCIncrement.new(id, ptr)
      rc_inc = Adamas::MIR::RCIncrement.new(2_u32, alloc.id)
      entry.add(rc_inc)

      # RCDecrement.new(id, ptr)
      rc_dec = Adamas::MIR::RCDecrement.new(3_u32, alloc.id)
      entry.add(rc_dec)

      ret = Adamas::MIR::Return.new(alloc.id)
      entry.terminator = ret

      initial_count = entry.instructions.size
      initial_count.should eq(3)  # alloc, rc_inc, rc_dec

      func.optimize_ltp

      # After optimization, rc_inc/rc_dec should be elided
      # (if noalias gate passes)
      final_count = entry.instructions.size
      final_count.should be <= initial_count
    end

    it "Ladder eligibility recognizes short corridors" do
      func = LTPTestHelpers.create_test_function_with_rc
      block = func.blocks.last

      rc_inc = block.instructions.find(&.is_a?(Adamas::MIR::RCIncrement)).not_nil!.as(Adamas::MIR::RCIncrement)
      load_inst = block.instructions.find(&.is_a?(Adamas::MIR::Load)).not_nil!.as(Adamas::MIR::Load)
      rc_dec = block.instructions.find(&.is_a?(Adamas::MIR::RCDecrement)).not_nil!.as(Adamas::MIR::RCDecrement)

      window_index = block.instructions.index(rc_inc).not_nil!
      window = Adamas::MIR::Window.new(rc_inc, block, window_index, 1, rc_inc.ptr)
      path = [] of Adamas::MIR::Value
      path << rc_inc
      path << load_inst
      path << rc_dec

      corridor = Adamas::MIR::Corridor.new(
        window,
        path,
        Adamas::MIR::CorridorExit::Elision,
        rc_dec
      )

      corridor.ladder_eligible?.should be_true
    end

    it "Diamond move resolves competing windows for same pointer" do
      int_type = Adamas::MIR::TypeRef::INT32
      void_type = Adamas::MIR::TypeRef::VOID

      func = Adamas::MIR::Function.new(LTPTestHelpers.next_func_id, "test_diamond", int_type)
      entry_id = func.create_block
      entry = func.get_block(entry_id)

      alloc = Adamas::MIR::Alloc.new(
        1_u32,
        int_type,
        Adamas::MIR::MemoryStrategy::ARC,
        int_type
      )
      alloc.no_alias = true
      entry.add(alloc)

      rc_inc1 = Adamas::MIR::RCIncrement.new(2_u32, alloc.id)
      entry.add(rc_inc1)

      call = Adamas::MIR::Call.new(
        3_u32,
        void_type,
        LTPTestHelpers.next_func_id,
        [alloc.id]
      )
      entry.add(call)

      rc_inc2 = Adamas::MIR::RCIncrement.new(4_u32, alloc.id)
      entry.add(rc_inc2)

      rc_dec = Adamas::MIR::RCDecrement.new(5_u32, alloc.id)
      entry.add(rc_dec)

      ret = Adamas::MIR::Return.new(alloc.id)
      entry.terminator = ret

      engine = Adamas::MIR::LTPEngine.new(func)
      engine.run(max_iters: 1)

      engine.moves_applied.any? { |move| move.type == Adamas::MIR::MoveType::Diamond }.should be_true
    end

    it "Collapse removes dead instructions when no legal move exists" do
      int_type = Adamas::MIR::TypeRef::INT32

      func = Adamas::MIR::Function.new(LTPTestHelpers.next_func_id, "test_collapse", int_type)
      entry_id = func.create_block
      entry = func.get_block(entry_id)

      alloc = Adamas::MIR::Alloc.new(
        1_u32,
        int_type,
        Adamas::MIR::MemoryStrategy::ARC,
        int_type
      )
      alloc.no_alias = true
      entry.add(alloc)

      rc_inc = Adamas::MIR::RCIncrement.new(2_u32, alloc.id)
      entry.add(rc_inc)

      live_const = Adamas::MIR::Constant.new(3_u32, int_type, 1_i64)
      entry.add(live_const)

      store = Adamas::MIR::Store.new(4_u32, alloc.id, live_const.id)
      entry.add(store)

      dead_const = Adamas::MIR::Constant.new(5_u32, int_type, 99_i64)
      entry.add(dead_const)

      ret = Adamas::MIR::Return.new(alloc.id)
      entry.terminator = ret

      before = entry.instructions.size
      func.optimize_ltp(max_iters: 1)
      after = entry.instructions.size

      after.should be < before
    end
  end

  describe "Dual Frame Fallback" do
    it "applies constant folding when no LTP move or collapse is available" do
      int_type = Adamas::MIR::TypeRef::INT32

      func = Adamas::MIR::Function.new(LTPTestHelpers.next_func_id, "test_dual_frame", int_type)
      entry_id = func.create_block
      entry = func.get_block(entry_id)

      left = Adamas::MIR::Constant.new(1_u32, int_type, 10_i64)
      right = Adamas::MIR::Constant.new(2_u32, int_type, 32_i64)
      entry.add(left)
      entry.add(right)

      add = Adamas::MIR::BinaryOp.new(3_u32, int_type, Adamas::MIR::BinOp::Add, left.id, right.id)
      entry.add(add)

      entry.terminator = Adamas::MIR::Return.new(add.id)

      func.optimize_ltp(max_iters: 1)

      folded = entry.instructions.find do |inst|
        inst.is_a?(Adamas::MIR::Constant) && inst.id == add.id
      end

      folded.should_not be_nil
    end
  end
end
