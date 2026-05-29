# Dry-run tracker for semantic identity layer.
#
# Runs as a side-channel during legacy compile path. Does NOT change
# any compilation behavior. Only observes and reports statistics about
# potential cache hits for body inference.
#
# Uses canonical DefInstanceKey (with real DefIdentity{arena_id, ExprId.index})
# when ExprId is available at the call site. Falls back to DryRunInstanceKey
# (with DryRunDefKey using node.object_id) when ExprId is not yet plumbed.
#
# Enable with: CRYSTAL_V2_IDENTITY_DRY_RUN=1

require "./semantic_type_id"
require "./def_identity"
require "./def_instance_key"

module Adamas::Compiler::Semantic
  # Fallback surrogate for call sites where ExprId is not yet available.
  # Will be removed once ExprId is plumbed to all call sites.
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
    # Track how many lookups use canonical vs surrogate identity
    getter canonical_lookups : Int32 = 0
    getter surrogate_lookups : Int32 = 0

    @canonical_keys : ::Hash(DefInstanceKey, Int32)
    @surrogate_keys : ::Hash(DryRunInstanceKey, Int32)

    def initialize
      @type_intern = SemanticTypeInternTable.new
      @canonical_keys = {} of DefInstanceKey => Int32
      @surrogate_keys = {} of DryRunInstanceKey => Int32
    end

    # Record using canonical DefInstanceKey (ExprId available).
    def record_canonical(key : DefInstanceKey) : Bool
      @total_lookups += 1
      @canonical_lookups += 1
      count = @canonical_keys[key]? || 0
      @canonical_keys[key] = count + 1
      if count > 0
        @cache_hits += 1
        true
      else
        @cache_misses += 1
        false
      end
    end

    # Record using surrogate key (ExprId not available).
    def record_surrogate(key : DryRunInstanceKey) : Bool
      @total_lookups += 1
      @surrogate_lookups += 1
      count = @surrogate_keys[key]? || 0
      @surrogate_keys[key] = count + 1
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
      canonical_unique = @canonical_keys.size
      surrogate_unique = @surrogate_keys.size
      canonical_dupes = @canonical_keys.count { |_, c| c > 1 }
      surrogate_dupes = @surrogate_keys.count { |_, c| c > 1 }
      total_unique = canonical_unique + surrogate_unique
      hit_rate = @total_lookups > 0 ? (@cache_hits * 100.0 / @total_lookups).round(1) : 0.0
      canonical_pct = @total_lookups > 0 ? (@canonical_lookups * 100.0 / @total_lookups).round(1) : 0.0
      io.puts "[IDENTITY_DRY_RUN] lookups=#{@total_lookups} hits=#{@cache_hits} misses=#{@cache_misses} hit_rate=#{hit_rate}%"
      io.puts "[IDENTITY_DRY_RUN] canonical=#{@canonical_lookups}(#{canonical_pct}%) surrogate=#{@surrogate_lookups}"
      io.puts "[IDENTITY_DRY_RUN] unique_keys=#{total_unique} (canonical=#{canonical_unique} surrogate=#{surrogate_unique}) interned_types=#{@type_intern.size}"
    end
  end
end
