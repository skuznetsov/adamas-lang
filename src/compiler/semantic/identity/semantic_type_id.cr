# Canonical semantic type identity for V2 compile path.
#
# SemanticTypeId is a table-backed interned identifier. Each unique semantic
# type gets a unique UInt32 id from the intern table. Two types with the
# same structure always get the same id. Hash collisions are impossible
# because identity is the interned UInt32, not a hash of the structure.
#
# This is the V2 equivalent of original Crystal's type object identity.
# It is used in DefInstanceKey for semantic caching and must NOT leak
# into HIR TypeRef or mangled names.

require "./def_identity"

module Adamas::Compiler::Semantic
  # Canonical semantic type identity — interned, collision-free.
  struct SemanticTypeId
    getter id : UInt32

    def initialize(@id : UInt32)
    end

    def ==(other : SemanticTypeId) : Bool
      @id == other.id
    end

    def hash(hasher)
      hasher = @id.hash(hasher)
      hasher
    end

    def to_s(io : IO) : Nil
      io << "SemType#" << @id
    end

    # Sentinel for unresolved/unknown types
    UNKNOWN = new(UInt32::MAX)
  end

  enum TypeKind : UInt8
    Primitive
    Class
    Struct
    Module
    Enum
    Union
    Tuple
    NamedTuple
    Proc
    Pointer
    Array
    Hash
    StaticArray
    Generic
    Alias
    Lib
  end

  # Structural key for the intern table. NOT the identity itself —
  # the identity is the SemanticTypeId assigned by the table.
  #
  # The key owns its dynamic components and never returns the retained array.
  # Otherwise caller mutation after insertion could change Hash equality and
  # make an interned semantic type unreachable.
  struct SemanticTypeKey
    getter kind : TypeKind
    getter name : String
    getter declaration_identity : DefIdentity?
    @type_params : Array(SemanticTypeId)

    def initialize(
      @kind : TypeKind,
      name : String,
      type_params : Array(SemanticTypeId),
      @declaration_identity : DefIdentity? = nil,
    )
      @name = name.dup
      @type_params = type_params.dup
    end

    def type_params : Array(SemanticTypeId)
      @type_params.dup
    end

    def ==(other : SemanticTypeKey) : Bool
      @kind == other.kind &&
        @name == other.name &&
        @declaration_identity == other.declaration_identity &&
        @type_params == other.@type_params
    end

    def hash(hasher)
      hasher = @kind.hash(hasher)
      hasher = @name.hash(hasher)
      hasher = @declaration_identity.hash(hasher)
      @type_params.hash(hasher)
    end
  end

  # Intern table: StructuralKey → unique SemanticTypeId.
  # Single source of truth for type identity.
  class SemanticTypeInternTable
    @table : ::Hash(SemanticTypeKey, SemanticTypeId)
    @reverse : ::Hash(SemanticTypeId, SemanticTypeKey)
    @next_id : UInt32 = 0

    def initialize
      @table = {} of SemanticTypeKey => SemanticTypeId
      @reverse = {} of SemanticTypeId => SemanticTypeKey
    end

    def intern(key : SemanticTypeKey) : SemanticTypeId
      if existing = @table[key]?
        return existing
      end
      id = SemanticTypeId.new(@next_id)
      @next_id += 1
      @table[key] = id
      @reverse[id] = key
      id
    end

    def lookup(id : SemanticTypeId) : SemanticTypeKey?
      @reverse[id]?
    end

    def size : Int32
      @table.size
    end

    # ── Convenience constructors ──

    def primitive(name : String) : SemanticTypeId
      intern(SemanticTypeKey.new(TypeKind::Primitive, name, [] of SemanticTypeId))
    end

    def named(name : String, kind : TypeKind) : SemanticTypeId
      intern(SemanticTypeKey.new(kind, name, [] of SemanticTypeId))
    end

    # Nominal declarations must include parser-owner identity. Local spelling
    # alone is not injective for nested or namespaced types.
    def nominal(
      name : String,
      kind : TypeKind,
      declaration_identity : DefIdentity,
      type_params : ::Array(SemanticTypeId) = [] of SemanticTypeId,
    ) : SemanticTypeId
      intern(SemanticTypeKey.new(kind, name, type_params, declaration_identity))
    end

    def generic(base_name : String, kind : TypeKind, args : ::Array(SemanticTypeId)) : SemanticTypeId
      intern(SemanticTypeKey.new(kind, base_name, args))
    end

    def union(variants : ::Array(SemanticTypeId)) : SemanticTypeId
      # Order-independent: sorted by id so Union(A|B) == Union(B|A)
      sorted = variants.sort_by(&.id)
      intern(SemanticTypeKey.new(TypeKind::Union, "", sorted))
    end

    def tuple(elements : ::Array(SemanticTypeId)) : SemanticTypeId
      intern(SemanticTypeKey.new(TypeKind::Tuple, "", elements))
    end

    def proc_type(arg_types : ::Array(SemanticTypeId), return_type : SemanticTypeId) : SemanticTypeId
      params = arg_types + [return_type]
      intern(SemanticTypeKey.new(TypeKind::Proc, "", params))
    end

    def pointer(element : SemanticTypeId) : SemanticTypeId
      intern(SemanticTypeKey.new(TypeKind::Pointer, "", [element]))
    end

    def static_array(element : SemanticTypeId, size_name : String) : SemanticTypeId
      intern(SemanticTypeKey.new(TypeKind::StaticArray, size_name, [element]))
    end

    # ── Normalized printable form ──

    def normalized_name(id : SemanticTypeId) : String
      key = @reverse[id]?
      return "Unknown" unless key

      case key.kind
      when .primitive?, .class?, .struct?, .module?, .enum?, .lib?, .alias?, .array?, .hash?
        if key.type_params.empty?
          key.name
        else
          "#{key.name}(#{key.type_params.map { |p| normalized_name(p) }.join(", ")})"
        end
      when .union?
        # Sort by printable name (not intern id) for stable display across runs
        key.type_params.map { |p| normalized_name(p) }.sort.join(" | ")
      when .tuple?
        "Tuple(#{key.type_params.map { |p| normalized_name(p) }.join(", ")})"
      when .named_tuple?
        "NamedTuple(#{key.name})"
      when .proc?
        if key.type_params.empty?
          "Proc(Nil)"
        else
          args = key.type_params[0...-1].map { |p| normalized_name(p) }
          ret = normalized_name(key.type_params.last)
          "Proc(#{args.join(", ")}, #{ret})"
        end
      when .pointer?
        "Pointer(#{normalized_name(key.type_params.first)})"
      when .static_array?
        "StaticArray(#{normalized_name(key.type_params.first)}, #{key.name})"
      when .generic?
        "#{key.name}(#{key.type_params.map { |p| normalized_name(p) }.join(", ")})"
      else
        key.name
      end
    end
  end
end
