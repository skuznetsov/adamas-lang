# Canonical cache key for typed method instances.
#
# DefInstanceKey identifies a unique instantiation of a method definition
# with specific semantic types at a call site. This is the V2 equivalent
# of original Crystal's DefInstanceKey in types.cr.
#
# Two calls to the same method with the same argument types get the same key.
# Different generic instantiations get different keys.
#
# Rules:
# - No mangled names in the key
# - No HIR::TypeRef in the key
# - No object_id as identity (use DefIdentity)
# - Keyed entirely by semantic identity
# - NameId values are table/session-local; keys and caches must not cross
#   compile-session boundaries

require "./semantic_type_id"
require "./def_identity"
require "./name_id"

module Adamas::Compiler::Semantic
  struct DefInstanceKey
    getter def_identity : DefIdentity
    getter receiver_type : SemanticTypeId?
    getter arg_types : SemanticTypeComponents
    getter block_type : SemanticTypeId?
    getter named_arg_types : ImmutableValueArray({NameId, SemanticTypeId})?

    def initialize(
      @def_identity : DefIdentity,
      @receiver_type : SemanticTypeId? = nil,
      arg_types : Array(SemanticTypeId) = [] of SemanticTypeId,
      @block_type : SemanticTypeId? = nil,
      named_arg_types : Array({NameId, SemanticTypeId})? = nil,
    )
      @arg_types = SemanticTypeComponents.new(arg_types)
      @named_arg_types = named_arg_types.try do |values|
        # The semantic cache key uses canonical NameId order. Source argument
        # order remains available to the resolver before this key is built.
        sorted = ImmutableValueArray({NameId, SemanticTypeId}).sorted_copy(values) { |entry| entry[0].id }
        index = 1
        while index < sorted.size
          if sorted[index - 1][0] == sorted[index][0]
            raise ArgumentError.new("duplicate named argument NameId=#{sorted[index][0].id}")
          end
          index += 1
        end
        sorted
      end
      validate_identity_scopes!
    end

    def ==(other : DefInstanceKey) : Bool
      @def_identity == other.def_identity &&
        @receiver_type == other.receiver_type &&
        @arg_types == other.arg_types &&
        @block_type == other.block_type &&
        @named_arg_types == other.named_arg_types
    end

    def hash(hasher)
      hasher = @def_identity.hash(hasher)
      hasher = @receiver_type.hash(hasher)
      hasher = @arg_types.hash(hasher)
      hasher = @block_type.hash(hasher)
      hasher = @named_arg_types.hash(hasher)
      hasher
    end

    def to_s(io : IO) : Nil
      io << "DefInst(" << @def_identity
      if recv = @receiver_type
        io << " recv=" << recv
      end
      unless @arg_types.empty?
        io << " args=[" << @arg_types.map(&.to_s).join(", ") << "]"
      end
      if bt = @block_type
        io << " block=" << bt
      end
      if named = @named_arg_types
        unless named.empty?
          io << " named=[" << named.map { |entry| "#{entry[0]}:#{entry[1]}" }.join(", ") << "]"
        end
      end
      io << ")"
    end

    private def validate_identity_scopes! : Nil
      semantic_scope : SemanticTypeId? = nil
      if receiver = @receiver_type
        semantic_scope = validate_semantic_type!(receiver, semantic_scope)
      end
      @arg_types.each do |type|
        semantic_scope = validate_semantic_type!(type, semantic_scope)
      end
      if block = @block_type
        semantic_scope = validate_semantic_type!(block, semantic_scope)
      end

      name_scope : NameId? = nil
      if named = @named_arg_types
        named.each do |name, type|
          unless name.canonical?
            raise ArgumentError.new("raw or UNKNOWN NameId cannot enter DefInstanceKey")
          end
          if previous = name_scope
            unless previous.same_owner?(name)
              raise ArgumentError.new("mixed NameId scopes cannot enter DefInstanceKey")
            end
          else
            name_scope = name
          end

          unless type.accepts_name?(name)
            raise ArgumentError.new("NameId is not owned by the SemanticTypeInternTable for this key")
          end
          semantic_scope = validate_semantic_type!(type, semantic_scope)
        end
      end
    end

    private def validate_semantic_type!(type : SemanticTypeId, scope : SemanticTypeId?) : SemanticTypeId
      unless type.canonical?
        raise ArgumentError.new("raw or UNKNOWN SemanticTypeId cannot enter DefInstanceKey")
      end
      if previous = scope
        unless previous.same_owner?(type)
          raise ArgumentError.new("mixed SemanticTypeId scopes cannot enter DefInstanceKey")
        end
        scope
      else
        type
      end
    end
  end
end
