module LLVM
  enum AtomicOrdering
    SequentiallyConsistent = 7
  end
end

module Atomic
  module Ops
    @[Primitive(:fence)]
    def self.fence(ordering : LLVM::AtomicOrdering, singlethread : Bool) : Nil
    end
  end
end

Atomic::Ops.fence(LLVM::AtomicOrdering::SequentiallyConsistent, false)
