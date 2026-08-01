# Compile-session owner for canonical semantic names and types.
#
# Callers share one registry instead of constructing parallel name or type
# interners. The registry owns all retained strings; NameId and SemanticTypeId
# are compact session-local references, not stable cross-run identifiers.

require "./name_id"
require "./semantic_type_id"

module Adamas::Compiler::Semantic
  class SemanticIdentityRegistry
    getter types : SemanticTypeInternTable

    @names : ::Hash(String, NameId)
    @name_by_id : ::Array(String)

    def initialize
      @types = SemanticTypeInternTable.new
      @names = {} of String => NameId
      @name_by_id = [] of String
    end

    def intern_name(name : String) : NameId
      if existing = @names[name]?
        return existing
      end
      if @name_by_id.size.to_u64 > UInt32::MAX.to_u64
        raise "semantic name registry exhausted UInt32 NameId space"
      end

      # Own the canonical spelling so a caller cannot couple key lifetime to a
      # transient string buffer or parser arena.
      owned_name = name.dup
      id = NameId.new(@name_by_id.size.to_u32)
      @names[owned_name] = id
      @name_by_id << owned_name
      id
    end

    def lookup_name(id : NameId) : String?
      @name_by_id[id.id]?
    end

    def name_count : Int32
      @name_by_id.size
    end
  end
end
