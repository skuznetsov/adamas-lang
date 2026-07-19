# Canonical in-process identity for a source-backed nominal type declaration.
#
# A short type name is diagnostic spelling, not semantic identity. The arena
# owner and declaration ExprId distinguish equal spellings in different
# namespaces without constructing a qualified-name String.

module Adamas::Compiler::Semantic
  struct TypeDeclarationIdentity
    getter arena_id : UInt64
    getter expr_index : Int32

    def initialize(@arena_id : UInt64, @expr_index : Int32)
      raise ArgumentError.new("type declaration ExprId cannot be invalid") if @expr_index < 0
    end

    def ==(other : TypeDeclarationIdentity) : Bool
      @arena_id == other.arena_id && @expr_index == other.expr_index
    end

    def hash(hasher)
      hasher = @arena_id.hash(hasher)
      @expr_index.hash(hasher)
    end
  end
end
