# Dry-run tracker for semantic identity layer.
#
# Runs as a side-channel during legacy compile path. Does NOT change
# any compilation behavior. Only observes and reports statistics about
# potential cache hits for body inference.
#
# IMPORTANT: This tracker uses DryRunDefKey, a TEMPORARY surrogate
# for def identity. It is NOT the canonical DefIdentity from Phase 1.
# The canonical DefIdentity requires {arena_id, ExprId.index}, which
# is not yet available at all infer_concrete_return_type_from_body
# call sites. Once ExprId plumbing is added, the surrogate will be
# replaced with real DefIdentity + DefInstanceKey.
#
# Enable with: CRYSTAL_V2_IDENTITY_DRY_RUN=1

require "./semantic_type_id"

module CrystalV2::Compiler::Semantic
  # Temporary surrogate for def identity in the dry-run tracker.
  # Uses node.object_id (heap address) as a stand-in for the canonical
  # DefIdentity{arena_id, ExprId.index} which requires ExprId plumbing
  # not yet available at all call sites.
  #
  # This is explicitly NOT DefIdentity — it is a surrogate that will
  # be replaced once ExprId is threaded through to inference call sites.
  struct DryRunDefKey
    getter arena_id : UInt64
    getter node_object_id : UInt64

    def initialize(@arena_id : UInt64, @node_object_id : UInt64)
    end

    def ==(other : DryRunDefKey) : Bool
      @arena_id == other.arena_id && @node_object_id == other.node_object_id
    end

    def hash(hasher)
      hasher = @arena_id.hash(hasher)
      hasher = @node_object_id.hash(hasher)
      hasher
    end
  end

  # Composite dry-run cache key: surrogate def key + semantic type context.
  # Mirrors DefInstanceKey structure but uses DryRunDefKey instead of
  # canonical DefIdentity.
  struct DryRunInstanceKey
    getter def_key : DryRunDefKey
    getter receiver_type : SemanticTypeId?
    getter arg_types : Array(SemanticTypeId)
    getter block_type : SemanticTypeId?

    def initialize(
      @def_key : DryRunDefKey,
      @receiver_type : SemanticTypeId? = nil,
      arg_types : Array(SemanticTypeId) = [] of SemanticTypeId,
      @block_type : SemanticTypeId? = nil
    )
      @arg_types = arg_types.dup
    end

    def ==(other : DryRunInstanceKey) : Bool
      @def_key == other.def_key &&
        @receiver_type == other.receiver_type &&
        @arg_types == other.arg_types &&
        @block_type == other.block_type
    end

    def hash(hasher)
      hasher = @def_key.hash(hasher)
      hasher = @receiver_type.hash(hasher)
      hasher = @arg_types.hash(hasher)
      hasher = @block_type.hash(hasher)
      hasher
    end
  end

  class IdentityDryRunTracker
    getter type_intern : SemanticTypeInternTable
    getter total_lookups : Int32 = 0
    getter cache_hits : Int32 = 0
    getter cache_misses : Int32 = 0

    @seen_keys : ::Hash(DryRunInstanceKey, Int32)

    def initialize
      @type_intern = SemanticTypeInternTable.new
      @seen_keys = {} of DryRunInstanceKey => Int32
    end

    # Record a body inference attempt. Returns true if this is a cache hit
    # (same key seen before), false if first encounter.
    def record_inference(key : DryRunInstanceKey) : Bool
      @total_lookups += 1
      count = @seen_keys[key]? || 0
      @seen_keys[key] = count + 1
      if count > 0
        @cache_hits += 1
        true
      else
        @cache_misses += 1
        false
      end
    end

    # Intern a type name into a SemanticTypeId.
    # Simplified: maps type name string → semantic type.
    # In Phase 2+, this will use proper semantic type resolution.
    def intern_type_name(name : String, kind : TypeKind = TypeKind::Class) : SemanticTypeId
      return @type_intern.primitive("Nil") if name == "Nil" || name == "Void"
      return @type_intern.primitive("Bool") if name == "Bool"
      return @type_intern.primitive("Int32") if name == "Int32"
      return @type_intern.primitive("Int64") if name == "Int64"
      return @type_intern.primitive("UInt32") if name == "UInt32"
      return @type_intern.primitive("UInt64") if name == "UInt64"
      return @type_intern.primitive("Float64") if name == "Float64"
      return @type_intern.primitive("String") if name == "String"
      return @type_intern.primitive("Char") if name == "Char"

      # Check for generic: Array(Int32) → generic("Array", [intern("Int32")])
      if paren = name.index('(')
        base = name[0...paren]
        # For dry-run, treat the whole name as identity (Phase 2 will parse args)
        @type_intern.named(name, kind)
      else
        @type_intern.named(name, kind)
      end
    end

    def dump(io : IO) : Nil
      unique_keys = @seen_keys.size
      duplicate_keys = @seen_keys.count { |_, c| c > 1 }
      hit_rate = @total_lookups > 0 ? (@cache_hits * 100.0 / @total_lookups).round(1) : 0.0
      io.puts "[IDENTITY_DRY_RUN] lookups=#{@total_lookups} hits=#{@cache_hits} misses=#{@cache_misses} hit_rate=#{hit_rate}%"
      io.puts "[IDENTITY_DRY_RUN] unique_keys=#{unique_keys} duplicate_keys=#{duplicate_keys} interned_types=#{@type_intern.size}"
      io.puts "[IDENTITY_DRY_RUN] NOTE: uses DryRunDefKey (node.object_id surrogate), not canonical DefIdentity"
    end
  end
end
