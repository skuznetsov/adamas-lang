# Canonical compile-session identity for an interned semantic name.
#
# NameId is deliberately separate from source spelling and HIR::StringId. It is
# meaningful only inside the SemanticIdentityRegistry that minted it; strings
# reappear only at diagnostic and serialization boundaries.

module Adamas::Compiler::Semantic
  struct NameId
    getter id : UInt32

    def initialize(@id : UInt32)
    end

    def ==(other : NameId) : Bool
      @id == other.id
    end

    def hash(hasher)
      @id.hash(hasher)
    end

    def to_s(io : IO) : Nil
      io << "Name#" << @id
    end
  end
end
