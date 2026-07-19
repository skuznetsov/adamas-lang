# Lightweight immutable carrier for the same-owner semantic→HIR/MIR bridge.
#
# This file deliberately does not require the semantic type graph or the
# CallResolution producer. The producer reopens the carrier after its own
# CallResolution definition and is the only place that can construct one.

require "./callsite_identity"
require "./def_instance_key"
require "./resolution_id"

module Adamas::Compiler::Semantic
  class CallResolutionHandoff
    getter resolution_id : ResolutionId
    getter callsite : CallsiteIdentity
    getter body_key : DefInstanceKey

    def ==(other : CallResolutionHandoff) : Bool
      @resolution_id == other.resolution_id &&
        @callsite == other.callsite &&
        @body_key == other.body_key
    end

    def hash(hasher)
      hasher = @resolution_id.hash(hasher)
      hasher = @callsite.hash(hasher)
      @body_key.hash(hasher)
    end

    # Kept private so callers cannot mint a carrier from raw component IDs.
    # `CallResolutionHandoff.from` is the only construction seam; repeated
    # conversion of one admitted resolution produces an equal value.
    private def initialize(
      @resolution_id : ResolutionId,
      @callsite : CallsiteIdentity,
      @body_key : DefInstanceKey,
    )
    end
  end
end
