lib AtomicMirOracleLibC
  fun putchar(value : Int32) : Int32
end

module LLVM
  enum AtomicOrdering
    Relaxed = 2
  end
end

module Atomic
  module Ops
    @[Primitive(:load_atomic)]
    def self.load(ptr : T*, ordering : LLVM::AtomicOrdering, volatile : Bool) : T forall T
    end

    # This overload is ordinary despite sharing the annotated method family.
    def self.load(ptr : Int32*, ordering : Int32, volatile : Bool) : Int32
      66_i32
    end
  end
end

value = 65_i32
observed = Atomic::Ops.load(pointerof(value), 2_i32, false)
AtomicMirOracleLibC.putchar(observed == 65_i32 ? 65_i32 : 66_i32)
AtomicMirOracleLibC.putchar(10_i32)
