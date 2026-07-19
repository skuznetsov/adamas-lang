# Canonical semantic type identity for V2 compile path.
#
# SemanticTypeId is a table-backed interned identifier. Each unique semantic
# type gets a unique UInt32 id from one SemanticTypeInternTable. Two types with
# the same structure always get the same id within that table. IDs are
# compile-session-local and must not cross table or cache boundaries.
#
# This is the V2 equivalent of original Crystal's type object identity.
# It is used in DefInstanceKey for semantic caching and must NOT leak
# into HIR TypeRef or mangled names.

require "./name_id"
require "./type_declaration_identity"

module Adamas::Compiler::Semantic
  # Canonical semantic type identity produced by SemanticTypeInternTable.
  # The raw initializer is for tests/transport only; its ordinal is never an
  # authority for any SemanticTypeInternTable.
  struct SemanticTypeId
    getter id : UInt32
    @owner : SemanticTypeInternTable?

    def initialize(@id : UInt32)
      @owner = nil
    end

    # Table-backed constructor. A caller may duplicate an issued ID, but an
    # unissued ordinal remains non-canonical because the owner validates it.
    def initialize(@owner : SemanticTypeInternTable?, @id : UInt32)
    end

    def ==(other : SemanticTypeId) : Bool
      @id == other.id && @owner.same?(other.@owner)
    end

    def hash(hasher)
      hasher = @owner.hash(hasher)
      @id.hash(hasher)
    end

    def owned_by?(owner : SemanticTypeInternTable) : Bool
      !!(@owner && @owner.not_nil!.same?(owner) && owner.issued_ordinal?(@id))
    end

    def unknown? : Bool
      @owner.nil? && @id == UInt32::MAX
    end

    def canonical? : Bool
      !!(@owner && @owner.not_nil!.issued_ordinal?(@id))
    end

    def same_owner?(other : SemanticTypeId) : Bool
      @owner.same?(other.@owner)
    end

    # Named arguments must come from the NameInternTable attached to the
    # SemanticTypeInternTable that issued this type ID.
    def accepts_name?(name : NameId) : Bool
      !!(@owner && canonical? && @owner.not_nil!.accepts_name?(name))
    end

    def to_s(io : IO) : Nil
      io << "SemType#" << @id
    end

    # Sentinel for unresolved/unknown types
    UNKNOWN = new(nil, UInt32::MAX)
  end

  # Shallow immutable-value carrier for an owned sequence used in a semantic
  # identity key. T must itself have immutable value semantics (for example,
  # SemanticTypeId or a tuple of IDs); this carrier does not deep-freeze T.
  # The backing Array is copied at construction and never exposed. Methods
  # returning a collection return a fresh copy, so a key remains safe as a
  # Hash key for its whole lifetime.
  struct ImmutableValueArray(T)
    @values : Array(T)

    def initialize(values : Array(T))
      @values = values.dup
    end

    # Sorts a caller-owned array into a fresh backing array before transferring
    # it to the carrier. The input is never borrowed, even though the private
    # constructor can adopt the internally-created sorted result.
    def self.sorted_copy(values : Array(T), &block : T -> U) : self forall U
      new(values.sort_by { |value| yield value }, true)
    end

    # Builds a fresh backing array and adopts it without a second defensive
    # copy. The caller's input array is read-only and is never retained.
    def self.map_owned(values : Array(U), &block : U -> T) : self forall U
      mapped = Array(T).new(values.size)
      values.each { |value| mapped << yield value }
      new(mapped, true)
    end

    private def initialize(@values : Array(T), _owned : Bool)
    end

    def [](index : Int) : T
      @values[index]
    end

    def each(&block : T ->) : Nil
      @values.each { |value| yield value }
    end

    def map(&block : T -> U) : Array(U) forall U
      @values.map { |value| yield value }
    end

    def empty? : Bool
      @values.empty?
    end

    def size : Int32
      @values.size
    end

    def first : T
      @values.first
    end

    def last : T
      @values.last
    end

    def to_a : Array(T)
      @values.dup
    end

    def ==(other : ImmutableValueArray(T)) : Bool
      return false unless @values.size == other.size

      index = 0
      while index < @values.size
        return false unless @values[index] == other[index]
        index += 1
      end
      true
    end

    def hash(hasher)
      @values.hash(hasher)
    end
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
    # Keep new kinds at the tail so existing serialized ordinals remain stable.
    Instance
  end

  alias SemanticTypeComponents = ImmutableValueArray(SemanticTypeId)

  # Structural key for the intern table. NOT the identity itself —
  # the identity is the SemanticTypeId assigned by the table.
  # NameId is table-local; raw spelling never participates directly in Hash
  # equality or hashing. For source-backed nominal types, declaration identity
  # plus the NameId owner replaces the spelling ordinal in equality/hash; the
  # short name is diagnostic only and keys from different sessions stay unequal.
  struct SemanticTypeKey
    getter kind : TypeKind
    getter name_id : NameId
    getter type_params : SemanticTypeComponents
    getter declaration_identity : TypeDeclarationIdentity?

    # Raw constructor accepts a NameId from the same compile-session name
    # table as the owning SemanticTypeInternTable. Cross-table use is invalid.
    def initialize(
      @kind : TypeKind,
      @name_id : NameId,
      type_params : Array(SemanticTypeId),
      @declaration_identity : TypeDeclarationIdentity? = nil,
    )
      @type_params = SemanticTypeComponents.new(type_params)
    end

    def initialize(
      @kind : TypeKind,
      @name_id : NameId,
      @type_params : SemanticTypeComponents,
      @declaration_identity : TypeDeclarationIdentity? = nil,
    )
    end

    def ==(other : SemanticTypeKey) : Bool
      @kind == other.kind &&
        @type_params == other.type_params &&
        @declaration_identity == other.declaration_identity &&
        (@declaration_identity ? @name_id.same_owner?(other.name_id) : @name_id == other.name_id)
    end

    def hash(hasher)
      hasher = @kind.hash(hasher)
      hasher = if declaration = @declaration_identity
                 declaration.hash(@name_id.owner_hash(hasher))
               else
                 @name_id.hash(hasher)
               end
      hasher = @type_params.hash(hasher)
      hasher
    end
  end

  # Intern table: StructuralKey → unique SemanticTypeId.
  # Owns one NameInternTable for the whole compile session. IDs, keys, and
  # caches produced here must not be mixed with another table instance.
  class SemanticTypeInternTable
    getter names : NameInternTable

    @table : ::Hash(SemanticTypeKey, SemanticTypeId)
    @reverse : ::Hash(SemanticTypeId, SemanticTypeKey)
    @names : NameInternTable
    @next_id : UInt32 = 0

    def initialize(@names : NameInternTable = NameInternTable.new)
      @table = {} of SemanticTypeKey => SemanticTypeId
      @reverse = {} of SemanticTypeId => SemanticTypeKey
    end

    # Returns a diagnostic copy; the NameInternTable's stored spelling never
    # escapes its ownership boundary.
    def name_for(id : NameId) : String?
      @names.lookup(id)
    end

    def intern(key : SemanticTypeKey) : SemanticTypeId
      validate_key!(key)
      if existing = @table[key]?
        return existing
      end
      id = allocate_id
      @table[key] = id
      @reverse[id] = key
      id
    end

    private def allocate_id : SemanticTypeId
      raise "SemanticTypeInternTable exhausted: SemanticTypeId::UNKNOWN is reserved" if @next_id == UInt32::MAX

      id = SemanticTypeId.new(self, @next_id)
      @next_id += 1
      id
    end

    def issued_ordinal?(id : UInt32) : Bool
      id != UInt32::MAX && id < @reverse.size.to_u32
    end

    def accepts_name?(name : NameId) : Bool
      @names.owns?(name)
    end

    private def validate_key!(key : SemanticTypeKey) : Nil
      if key.name_id.unknown?
        unless unnamed_kind?(key.kind)
          raise ArgumentError.new("named semantic type #{key.kind} requires an owned NameId")
        end
      elsif unnamed_kind?(key.kind)
        raise ArgumentError.new("unnamed semantic type #{key.kind} must use NameId::UNKNOWN")
      elsif !@names.owns?(key.name_id)
        raise ArgumentError.new("foreign NameId cannot be admitted to this semantic type table")
      end

      key.type_params.each do |component|
        unless component.owned_by?(self)
          raise ArgumentError.new("foreign or raw SemanticTypeId component cannot be admitted")
        end
      end
    end

    private def unnamed_kind?(kind : TypeKind) : Bool
      case kind
      when .union?, .tuple?, .proc?, .pointer?
        true
      else
        false
      end
    end

    private def intern_named(kind : TypeKind, spelling : String, type_params : Array(SemanticTypeId)) : SemanticTypeId
      name_id = @names.intern(spelling)
      intern(SemanticTypeKey.new(kind, name_id, type_params))
    end

    def lookup(id : SemanticTypeId) : SemanticTypeKey?
      return nil unless id.owned_by?(self)
      @reverse[id]?
    end

    def size : Int32
      @table.size
    end

    # ── Convenience constructors ──

    def primitive(name : String) : SemanticTypeId
      intern_named(TypeKind::Primitive, name, [] of SemanticTypeId)
    end

    def named(name : String, kind : TypeKind) : SemanticTypeId
      intern_named(kind, name, [] of SemanticTypeId)
    end

    def generic(base_name : String, kind : TypeKind, args : ::Array(SemanticTypeId)) : SemanticTypeId
      intern_named(kind, base_name, args)
    end

    def nominal(
      name : String,
      kind : TypeKind,
      declaration_identity : TypeDeclarationIdentity,
      args : ::Array(SemanticTypeId),
    ) : SemanticTypeId
      unless kind.class? || kind.instance? || kind.struct? || kind.module? || kind.enum?
        raise ArgumentError.new("#{kind} is not a nominal semantic type kind")
      end

      name_id = @names.intern(name)
      intern(SemanticTypeKey.new(kind, name_id, args, declaration_identity))
    end

    def union(variants : ::Array(SemanticTypeId)) : SemanticTypeId
      # Order-independent: sorted by id so Union(A|B) == Union(B|A)
      components = SemanticTypeComponents.sorted_copy(variants) { |id| id.id }
      intern(SemanticTypeKey.new(TypeKind::Union, NameId::UNKNOWN, components))
    end

    def tuple(elements : ::Array(SemanticTypeId)) : SemanticTypeId
      intern(SemanticTypeKey.new(TypeKind::Tuple, NameId::UNKNOWN, elements))
    end

    def proc_type(arg_types : ::Array(SemanticTypeId), return_type : SemanticTypeId) : SemanticTypeId
      params = arg_types + [return_type]
      intern(SemanticTypeKey.new(TypeKind::Proc, NameId::UNKNOWN, params))
    end

    def pointer(element : SemanticTypeId) : SemanticTypeId
      intern(SemanticTypeKey.new(TypeKind::Pointer, NameId::UNKNOWN, [element]))
    end

    def static_array(element : SemanticTypeId, size_name : String) : SemanticTypeId
      intern_named(TypeKind::StaticArray, size_name, [element])
    end

    # ── Normalized printable form ──

    def normalized_name(id : SemanticTypeId) : String
      return "Unknown" unless id.owned_by?(self)
      key = @reverse[id]?
      return "Unknown" unless key
      key_name = @names.lookup(key.name_id) || "Unknown"

      case key.kind
      when .primitive?, .class?, .instance?, .struct?, .module?, .enum?, .lib?, .alias?, .array?, .hash?
        if key.type_params.empty?
          key_name
        else
          "#{key_name}(#{key.type_params.map { |p| normalized_name(p) }.join(", ")})"
        end
      when .union?
        # Sort by printable name (not intern id) for stable display across runs
        key.type_params.map { |p| normalized_name(p) }.sort.join(" | ")
      when .tuple?
        "Tuple(#{key.type_params.map { |p| normalized_name(p) }.join(", ")})"
      when .named_tuple?
        "NamedTuple(#{key_name})"
      when .proc?
        if key.type_params.empty?
          "Proc(Nil)"
        else
          args = key.type_params.to_a[0...-1].map { |p| normalized_name(p) }
          ret = normalized_name(key.type_params.last)
          "Proc(#{args.join(", ")}, #{ret})"
        end
      when .pointer?
        "Pointer(#{normalized_name(key.type_params.first)})"
      when .static_array?
        "StaticArray(#{normalized_name(key.type_params.first)}, #{key_name})"
      when .generic?
        "#{key_name}(#{key.type_params.map { |p| normalized_name(p) }.join(", ")})"
      else
        key_name
      end
    end
  end
end
