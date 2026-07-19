# Compile-session scoped numeric identity for named arguments and other names.
#
# NameId is a compile-session/table-local ordinal carried by semantic keys.
# The original spelling is retained only by NameInternTable for diagnostics or
# reverse lookup. IDs and keys must not cross NameInternTable instances.

module Adamas::Compiler::Semantic
  struct NameId
    getter id : UInt32
    @owner : NameInternTable?

    # Raw construction is for tests/transport only. Its ordinal may compare by
    # value, but it is never authoritative for any NameInternTable.
    def initialize(@id : UInt32)
      @owner = nil
    end

    # Table-backed constructor. A caller may duplicate an issued ID, but an
    # unissued ordinal remains non-canonical because the owner validates it.
    def initialize(@owner : NameInternTable?, @id : UInt32)
    end

    def ==(other : NameId) : Bool
      @id == other.id && @owner.same?(other.@owner)
    end

    def hash(hasher)
      hasher = @owner.hash(hasher)
      @id.hash(hasher)
    end

    def owned_by?(owner : NameInternTable) : Bool
      !!(@owner && @owner.not_nil!.same?(owner) && owner.issued_ordinal?(@id))
    end

    def unknown? : Bool
      @owner.nil? && @id == UInt32::MAX
    end

    def canonical? : Bool
      !!(@owner && @owner.not_nil!.issued_ordinal?(@id))
    end

    def same_owner?(other : NameId) : Bool
      @owner.same?(other.@owner)
    end

    def to_s(io : IO) : Nil
      io << "Name#" << @id
    end

    UNKNOWN = new(nil, UInt32::MAX)
  end

  # Owns each spelling once for one compile session. There is no process-wide
  # or compiler-global name table.
  class NameInternTable
    @by_name : ::Hash(String, NameId)
    @names : ::Array(String)
    @next_id : UInt32 = 0

    def initialize
      @by_name = {} of String => NameId
      @names = [] of String
    end

    def intern(name : String) : NameId
      if existing = @by_name[name]?
        return existing
      end

      id = allocate_id
      # The table owns this one spelling. The caller may mutate its String
      # after this call without changing the hash key or reverse lookup.
      owned_name = String.build { |io| io << name }
      @by_name[owned_name] = id
      @names << owned_name
      id
    end

    def lookup(name : String) : NameId?
      @by_name[name]?
    end

    def lookup(id : NameId) : String?
      return nil unless id.owned_by?(self)
      return nil if id.id >= @names.size.to_u32

      stored = @names[id.id.to_i]?
      stored.try { |name| String.build { |io| io << name } }
    end

    def owns?(id : NameId) : Bool
      id.owned_by?(self)
    end

    def issued_ordinal?(id : UInt32) : Bool
      id != UInt32::MAX && id < @names.size.to_u32
    end

    def size : Int32
      @names.size
    end

    private def allocate_id : NameId
      raise "NameInternTable exhausted: NameId::UNKNOWN is reserved" if @next_id == UInt32::MAX

      id = NameId.new(self, @next_id)
      @next_id += 1
      id
    end
  end
end
