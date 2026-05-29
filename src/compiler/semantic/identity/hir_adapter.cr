# One-way adapter: SemanticTypeId → HIR::TypeRef.
#
# This adapter sits at the emission boundary between the semantic layer
# and the HIR builder. It converts canonical semantic type identities
# into HIR-specific TypeRef values for code generation.
#
# The mapping is one-way: semantic → HIR. HIR TypeRef should never
# leak back into semantic caches or DefInstanceKey.

require "../identity/semantic_type_id"

module Adamas::Compiler::Semantic
  class SemanticToHIRAdapter
    @semantic_to_hir : ::Hash(SemanticTypeId, Adamas::HIR::TypeRef)
    @hir_to_semantic : ::Hash(Adamas::HIR::TypeRef, SemanticTypeId)

    def initialize
      @semantic_to_hir = {} of SemanticTypeId => Adamas::HIR::TypeRef
      @hir_to_semantic = {} of Adamas::HIR::TypeRef => SemanticTypeId
    end

    # Map a semantic type to an HIR TypeRef.
    # The caller must provide the TypeRef (from HIR type registration).
    def register(semantic_id : SemanticTypeId, type_ref : Adamas::HIR::TypeRef) : Nil
      @semantic_to_hir[semantic_id] = type_ref
      @hir_to_semantic[type_ref] = semantic_id
    end

    # Look up existing mapping (returns nil if not yet mapped).
    def resolve(semantic_id : SemanticTypeId) : Adamas::HIR::TypeRef?
      @semantic_to_hir[semantic_id]?
    end

    # Reverse lookup (for diagnostics/debugging only).
    def semantic_for(type_ref : Adamas::HIR::TypeRef) : SemanticTypeId?
      @hir_to_semantic[type_ref]?
    end

    def size : Int32
      @semantic_to_hir.size
    end
  end
end
