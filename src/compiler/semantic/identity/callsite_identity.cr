# In-process identity for a semantic callsite.
#
# ExprId is only an index into one arena. Carry the arena owner alongside it
# when a call decision crosses the semantic API boundary.

module Adamas::Compiler::Semantic
  struct CallsiteIdentity
    getter arena_id : UInt64
    getter expr_index : Int32

    def initialize(@arena_id : UInt64, @expr_index : Int32)
      raise ArgumentError.new("callsite ExprId cannot be invalid") if @expr_index < 0
    end

    def ==(other : CallsiteIdentity) : Bool
      @arena_id == other.arena_id && @expr_index == other.expr_index
    end

    def hash(hasher)
      hasher = @arena_id.hash(hasher)
      @expr_index.hash(hasher)
    end

    def same_arena?(other : CallsiteIdentity) : Bool
      @arena_id == other.arena_id
    end

    def to_s(io : IO) : Nil
      io << "Call@" << @arena_id.to_s(16) << ":" << @expr_index
    end
  end
end
