# Owner-scoped identity for one semantic call-resolution decision.
#
# A ResolutionId is deliberately not an ExprId, DefIdentity, or mangled name:
# one callsite may be re-resolved, and two callsites may select the same Def.
# The ResolutionScope owns the ordinal stream and keeps IDs valid only for the
# semantic session that issued them. The current semantic engine is
# single-threaded; issue/claim ordering is deliberately not synchronized.

require "../../frontend/ast"
require "./callsite_identity"
require "./def_identity"
require "./semantic_type_id"

module Adamas::Compiler::Semantic
  class ResolutionScope
    getter arena_id : UInt64
    @next_id : UInt64 = 0
    @pending_id : UInt64? = nil

    def initialize(
      @arena_owner : Frontend::AstArena,
      @semantic_owner : SemanticTypeInternTable,
    )
      @arena_id = @arena_owner.object_id.to_u64
    end

    def owns_semantic_context?(owner : SemanticTypeInternTable) : Bool
      @semantic_owner.same?(owner)
    end

    # Revalidate coordinates through the retained arena before a semantic
    # decision is allowed to cross into downstream metadata.
    def owns_source_coordinates?(
      callsite : CallsiteIdentity,
      def_identity : DefIdentity,
    ) : Bool
      return false unless callsite.arena_id == @arena_id && def_identity.arena_id == @arena_id
      return false if callsite.expr_index >= @arena_owner.size
      return false if def_identity.expr_index < 0 || def_identity.expr_index >= @arena_owner.size

      call_expr_id = Frontend::ExprId.new(callsite.expr_index)
      def_expr_id = Frontend::ExprId.new(def_identity.expr_index)
      @arena_owner[call_expr_id].is_a?(Frontend::CallNode) &&
        @arena_owner[def_expr_id].is_a?(Frontend::DefNode)
    end

    def issue : ResolutionId
      raise "ResolutionScope exhausted" if @next_id == UInt64::MAX
      raise "ResolutionScope already has a pending ResolutionId" if @pending_id

      resolution_id = ResolutionId.new(self, @next_id)
      @pending_id = @next_id
      resolution_id
    end

    def issued?(id : UInt64) : Bool
      id < @next_id || @pending_id == id
    end

    def claim!(resolution_id : ResolutionId) : Nil
      unless resolution_id.owned_by?(self)
        raise ArgumentError.new("ResolutionId is not owned by this scope")
      end
      if resolution_id.id < @next_id
        raise ArgumentError.new("ResolutionId has already been claimed")
      end
      if @pending_id != resolution_id.id
        raise ArgumentError.new("ResolutionId must be claimed in issue order")
      end

      @pending_id = nil
      @next_id += 1
    end

    def cancel!(resolution_id : ResolutionId) : Nil
      return unless resolution_id.owned_by?(self) && @pending_id == resolution_id.id

      # Never reuse a rejected ordinal. Reissuing the same owner/id pair would
      # make a stale token canonical again (ABA) and let it claim unrelated
      # call facts. Gaps are valid; ResolutionId density is not an invariant.
      @pending_id = nil
      @next_id += 1
    end
  end

  struct ResolutionId
    getter id : UInt64
    @owner : ResolutionScope?

    # Raw construction is retained for diagnostics/tests only. It is not a
    # canonical ID and cannot be admitted by an owner-scoped carrier.
    def initialize(@id : UInt64)
      @owner = nil
    end

    def initialize(@owner : ResolutionScope?, @id : UInt64)
    end

    def ==(other : ResolutionId) : Bool
      @id == other.id && @owner.same?(other.@owner)
    end

    def hash(hasher)
      hasher = @owner.hash(hasher)
      @id.hash(hasher)
    end

    def owned_by?(owner : ResolutionScope) : Bool
      !!(@owner && @owner.not_nil!.same?(owner) && owner.issued?(@id))
    end

    def canonical? : Bool
      !!(@owner && @owner.not_nil!.issued?(@id))
    end

    def owns_source_coordinates?(
      callsite : CallsiteIdentity,
      def_identity : DefIdentity,
    ) : Bool
      owner = @owner
      !!(owner && owner.owns_source_coordinates?(callsite, def_identity))
    end

    def unknown? : Bool
      @owner.nil? && @id == UInt64::MAX
    end

    def same_owner?(other : ResolutionId) : Bool
      @owner.same?(other.@owner)
    end

    def cancel_pending_issue! : Nil
      @owner.try(&.cancel!(self))
    end

    def to_s(io : IO) : Nil
      io << "Resolution#" << @id
    end

    UNKNOWN = new(nil, UInt64::MAX)
  end
end
