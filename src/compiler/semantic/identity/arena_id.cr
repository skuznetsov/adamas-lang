# Compile-scoped identity for a parser arena owner.
#
# ArenaId is intentionally separate from an arena address. The registry keeps
# the owner reference only for the lifetime of one compiler instance and
# assigns a small monotonic value that can be carried by semantic records.
# ArenaId values are not stable across compilations and must not be derived from
# source strings or used as cross-run identifiers.

require "../../frontend/ast"

module Adamas::Compiler::Semantic
  struct ArenaId
    getter value : UInt64

    INVALID = new(0_u64)

    def initialize(@value : UInt64)
    end

    def valid? : Bool
      @value != 0_u64
    end

    def ==(other : ArenaId) : Bool
      @value == other.value
    end

    def hash(hasher)
      @value.hash(hasher)
    end

    def to_s(io : IO) : Nil
      io << "Arena#" << @value
    end
  end

  # One owner table per compile. The reference-keyed map is deliberately kept
  # inside this registry: semantic callers receive only ArenaId and never use
  # an arena address as a cache or identity key.
  class ArenaIdentityRegistry
    @ids : Hash(Adamas::Compiler::Frontend::ArenaLike, ArenaId)
    @next_value : UInt64

    def initialize
      @ids = {} of Adamas::Compiler::Frontend::ArenaLike => ArenaId
      @next_value = 1_u64
    end

    def id_for(owner : Adamas::Compiler::Frontend::ArenaLike) : ArenaId
      if existing = @ids[owner]?
        return existing
      end

      raise "ArenaId registry exhausted for this compilation" if @next_value == UInt64::MAX
      id = ArenaId.new(@next_value)
      @next_value += 1_u64
      @ids[owner] = id
      id
    end

    def registered?(owner : Adamas::Compiler::Frontend::ArenaLike) : Bool
      @ids.has_key?(owner)
    end

    def size : Int32
      @ids.size
    end
  end
end
