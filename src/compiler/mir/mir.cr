# Mid-Level IR (MIR) for Crystal v2
#
# SSA form with explicit memory operations, ready for LLVM lowering.
# Key differences from HIR:
#   - SSA: each value assigned exactly once
#   - Explicit control flow: basic blocks, phi nodes
#   - Explicit memory: alloc, free, rc_inc, rc_dec
#   - Closures lowered to struct + function pointer
#
# See docs/codegen_architecture.md Section 4 for specification.

# The struct-value ABI repr contract (docs/abi_struct_value_sdd.md §3). MIR::Type
# memoizes its `inline_value?` bit via this module. Crystal resolves the mutual
# type references (LayoutContract reads MIR::TypeKind; MIR::Type calls
# LayoutContract) globally, so require order is irrelevant.
require "../layout_contract"
require "../semantic/identity/call_resolution_handoff"

module Adamas::MIR
  # ═══════════════════════════════════════════════════════════════════════════
  # TYPE ALIASES
  # ═══════════════════════════════════════════════════════════════════════════

  alias ValueId = UInt32
  alias BlockId = UInt32
  alias FunctionId = UInt32
  alias TypeId = UInt32

  {% if flag?(:i386) || flag?(:arm) || flag?(:wasm32) %}
    TARGET_POINTER_BYTES_U64 = 4_u64
    TARGET_POINTER_ALIGN_U32 = 4_u32
  {% else %}
    TARGET_POINTER_BYTES_U64 = 8_u64
    TARGET_POINTER_ALIGN_U32 = 8_u32
  {% end %}

  # ═══════════════════════════════════════════════════════════════════════════
  # MEMORY STRATEGY (assigned during HIR → MIR lowering)
  # ═══════════════════════════════════════════════════════════════════════════

  enum MemoryStrategy
    Stack       # LLVM alloca, automatic cleanup
    Slab        # Fiber-local arena, bump allocation
    ARC         # Reference counting (non-atomic)
    AtomicARC   # Reference counting (atomic, thread-safe)
    GC          # Garbage collected (Boehm GC)

    def to_s : String
      case self
      when Stack     then "stack"
      when Slab      then "slab"
      when ARC       then "arc"
      when AtomicARC then "atomic_arc"
      else                "gc"  # GC
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TYPE KIND - What kind of type this is
  # ═══════════════════════════════════════════════════════════════════════════

  enum TypeKind
    Void
    Bool
    Int8
    Int16
    Int32
    Int64
    Int128
    UInt8
    UInt16
    UInt32
    UInt64
    UInt128
    Float32
    Float64
    Char
    Symbol
    Pointer
    Reference
    Struct
    Union
    Proc
    Tuple
    Array
    Enum

    def primitive?
      case self
      when Void, Bool, Int8, Int16, Int32, Int64, Int128,
           UInt8, UInt16, UInt32, UInt64, UInt128,
           Float32, Float64, Char, Symbol
        true
      else
        false
      end
    end

    def integer?
      case self
      when Int8, Int16, Int32, Int64, Int128,
           UInt8, UInt16, UInt32, UInt64, UInt128
        true
      else
        false
      end
    end

    def signed_integer?
      case self
      when Int8, Int16, Int32, Int64, Int128 then true
      else                                        false
      end
    end

    def floating?
      self == Float32 || self == Float64
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONTAINER ELEMENT REPRESENTATION (ABI rework — storage slice scaffold)
  # ═══════════════════════════════════════════════════════════════════════════
  #
  # Three-way classification of HOW a value of an element type lives inside a
  # container buffer (Array / Slice / Pointer(T)). Produced by a REGISTRY-BACKED
  # classifier that ALSO needs the HIR lib-struct set (a bare MIR::Type cannot
  # answer it: the leaf-storage-POD test must resolve each Field.type_ref through
  # the TypeRegistry, and the lib-struct reject needs the HIR lib set — neither is
  # reachable from LLVM). So the classification is computed ONCE during HIR→MIR
  # and STORED on `Type#container_elem_repr` as a fixed ABI label; later phases
  # (LLVM lowering) READ that label and never re-derive the HIR-only heuristic.
  # This is the SINGLE label the per-element lowering sites will switch on,
  # replacing today's scattered ad-hoc struct/family checks
  # (container_elem_storage_size_u64, emit_array_get/_set, Pointer(T)#<<,
  # unsafe_fetch).
  #
  # PLUMBING STEP (additive, behavior-neutral): the label is computed + stored +
  # logged under the ADAMAS_INLINE_POD_CONTAINERS gate but is NOT yet read by any
  # lowering site — none of the sites above are touched, and gate OFF stores
  # nothing. A later gated behavior-changing commit wires InlineValueCopy
  # (copy-on-store + escape-aware copy-on-load) into them as ONE atomic ABI slice.
  enum ContainerElemRepr
    # Default / EXISTING lowering, left unchanged — NOT "the slot is a pointer".
    # The name is deliberately *not* `PointerSlot`: the existing element-sizing
    # cascade (llvm_backend.cr container_elem_storage_size_u64_impl) stores
    # primitives / wide unions / primitive tuples INLINE-BY-VALUE, while plain /
    # nested-carrier / ref-owning structs and classes are pointer slots. So this
    # arm means "the classifier did NOT positively pick one of the two inline
    # cases below — keep whatever the existing per-element lowering already does".
    # Lowering sites must treat it as a passthrough (do NOT branch on it as if it
    # implied pointer storage), so primitive / union / tuple paths stay identical.
    ExistingLowering

    # Inline storage where element ACCESS returns the slot ADDRESS (no load/copy)
    # by design — the already-implemented inline-container families (Slice( /
    # StaticArray( / Hash::Entry(). Current behavior; MUST stay unchanged.
    InlineAddress

    # NEW: inline storage with copy-on-store AND escape-aware copy-on-load — a
    # leaf-storage-POD struct (every field primitive / enum / raw pointer; no
    # nested struct / tuple / union / ref; size in 1..16; non-union; non-lib).
    InlineValueCopy
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ABI FACTS — Array bulk-op coverage (A' mini-AbiFacts bridge)
  # ═══════════════════════════════════════════════════════════════════════════
  #
  # A leaf-POD value struct C can only get inline Array(C) storage if the WHOLE
  # bulk-op family (store/load + memmove/memcpy/memset + alloc/realloc) on the
  # Array(C) @buffer is provably stride-consistent. These typed facts record, per
  # bulk extern_call inside a monomorphic Array(C)# body, whether it is covered —
  # proven STRUCTURALLY (@buffer provenance + element-stride byte count), never by
  # name alone. A later behavior slice READS these facts and rewrites only the
  # covered sites; an uncovered/heterogeneous op makes C fail-closed (NOT inline).
  enum ArrayBulkOpKind
    MoveCopySameElem  # memmove/memcpy over the Array(C) @buffer at element stride
    Clear             # memset over the Array(C) @buffer at element stride
    AllocRealloc      # @buffer malloc/realloc sized by capacity * element stride
    Heterogeneous     # a copy whose source is NOT the same Array(C) representation
    Uncovered         # provenance/stride not proven, or an unsupported bulk op
  end

  # Why a bulk op was (not) classified as covered — for the read-only census report
  # and for fail-closed diagnostics.
  enum ArrayBulkCoverageReason
    Covered
    NoBufferProvenance  # pointer arg does not trace to the self @buffer load
    NoStrideProof       # byte count / capacity does not trace to element stride
    HeterogeneousSource # copy source is a foreign repr (Slice/other/to_unsafe/union)
    UnsupportedOp       # a bulk op the rewrite does not (yet) handle
  end

  struct MaterializationContractFacts
    getter required_contract : String
    getter body_symbol : String
    getter call_symbol_hint : String
    getter symbol_relation : String
    getter identity_status : String

    def initialize(
      @required_contract : String,
      @body_symbol : String,
      @call_symbol_hint : String,
      @symbol_relation : String,
      @identity_status : String,
    )
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FIELD - Struct/class field definition
  # ═══════════════════════════════════════════════════════════════════════════

  struct Field
    getter name : String
    getter type_ref : TypeRef
    getter offset : UInt32
    getter flags : UInt32

    FLAG_NILABLE  = 0x0001_u32
    FLAG_CAPTURED = 0x0002_u32  # Captured in closure

    def initialize(@name, @type_ref, @offset, @flags = 0_u32)
    end

    def nilable? : Bool
      (@flags & FLAG_NILABLE) != 0
    end

    def captured? : Bool
      (@flags & FLAG_CAPTURED) != 0
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TYPE - Full type definition with metadata
  # ═══════════════════════════════════════════════════════════════════════════

  class Type
    getter id : TypeId
    property kind : TypeKind
    property name : String
    property size : UInt64
    property alignment : UInt32
    getter fields : Array(Field)?
    getter variants : Array(Type)?     # For union types
    getter element_types : Array(Type)? # For tuples
    getter element_type : Type?         # For arrays/pointers
    getter parent_type_id : TypeId?
    property is_closure : Bool = false

    # Fixed container-element ABI label (ContainerElemRepr), set ONCE during
    # HIR→MIR after the registry/sizes/fields have settled. Unlike `inline_value?`
    # this CANNOT be a lazy self-memo: classifying it needs the TypeRegistry (to
    # resolve field type_refs) and the HIR lib-struct set, neither of which a bare
    # Type holds — so HIRToMIRLowering computes it and writes it here, and LLVM
    # lowering only READS it (one classification, no lib-info loss, no drift). nil
    # = not (yet) classified; the gate that populates it is off, so the default
    # path leaves it nil and no lowering site reads it.
    property container_elem_repr : ContainerElemRepr? = nil

    # A' step (c→annotation): durable per-type "inline-value SAFE" flag. Set ONCE
    # during HIR→MIR by the same {bv && !vd && !erased_flow} analysis the safe-set
    # probe reports — true iff every observed access of this type as an Array
    # element goes through the @buffer-base value path (no raw-Pointer value_derived
    # access, and Array(T) never flows into a type-erased body). A later behavior
    # slice will inline-store ONLY types with this flag AND only at the GEP sites
    # marked array_buffer_value (see GetElementPtrDynamic). nil/false = not eligible;
    # the gate that populates it is off by default, so the default path leaves it
    # false and no lowering site reads it.
    property inline_value_safe : Bool = false

    # A' mini-AbiFacts: the COMPOSED behavior-eligibility bit. True iff
    #   inline_value_safe(C) && the whole Array(C) bulk-op family is provably
    #   covered (no Heterogeneous/Uncovered op) && no value_derived/to_unsafe escape.
    # This — NOT inline_value_safe alone — is what a later inline-Array-storage
    # behavior slice gates on. Default false; populated only under the facts gate;
    # no lowering site reads it yet.
    property inline_array_storage_eligible : Bool = false

    def initialize(@id, @kind, @name, @size, @alignment)
    end

    def is_value_type? : Bool
      @kind == TypeKind::Struct
    end

    # Memoized struct-value ABI repr bit (docs/abi_struct_value_sdd.md §3): true
    # when a value of this type lives INLINE at its slot, false when the slot
    # holds an 8-byte pointer. The authority is the pure LayoutContract function;
    # this is only a CACHE of it for the MIR/LLVM phases (HIR calls the function
    # directly, pre-registry).
    #
    # LAZY (computed on first read), not eager at creation: some types have their
    # registry size updated after the Type is first created (e.g. String 8->12
    # when ivars are discovered), so an eager bit could freeze a stale small/large
    # carrier decision. Reading after the size settles avoids that hazard.
    #
    # `is_lib` defaults false: lib (C ABI) structs keep their dedicated path
    # (SDD §5) and their readers pass is_lib explicitly to LayoutContract rather
    # than relying on this memo.
    #
    # STEP 1a: introduced but NOT read by any oracle yet (additive/unused). Steps
    # 1b/1c wire the readers; step 2 freezes the bit.
    @inline_value_memo : Bool? = nil

    def inline_value?(is_lib : Bool = false) : Bool
      memo = @inline_value_memo
      return memo unless memo.nil?
      result = Adamas::LayoutContract.inline_value?(@kind, @size, @name, is_lib)
      @inline_value_memo = result
      result
    end

    def signed? : Bool
      @kind.signed_integer?
    end

    def add_field(name : String, type_ref : TypeRef, offset : UInt32, flags : UInt32 = 0_u32)
      @fields ||= [] of Field
      @fields.not_nil! << Field.new(name, type_ref, offset, flags)
    end

    def add_variant(variant : Type)
      @variants ||= [] of Type
      @variants.not_nil! << variant
    end

    def add_element_type(element : Type)
      @element_types ||= [] of Type
      @element_types.not_nil! << element
    end

    def set_element_type(@element_type : Type)
    end

    def set_parent_type_id(@parent_type_id : TypeId)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TYPE REGISTRY - Stores all type definitions
  # ═══════════════════════════════════════════════════════════════════════════

  class TypeRegistry
    getter types : Array(Type)
    @next_type_id : TypeId
    @types_by_id : Hash(TypeId, Type)
    @types_by_name : Hash(String, Type)

    def initialize
      @types = [] of Type
      @types_by_id = {} of TypeId => Type
      @types_by_name = {} of String => Type
      @next_type_id = 100_u32  # Reserve 0-99 for primitive types

      # Register primitive types
      register_primitive(TypeRef::VOID, TypeKind::Void, "Void", 0, 1)
      register_primitive(TypeRef::NIL, TypeKind::Void, "Nil", 0, 1)
      register_primitive(TypeRef::BOOL, TypeKind::Bool, "Bool", 1, 1)
      register_primitive(TypeRef::INT8, TypeKind::Int8, "Int8", 1, 1)
      register_primitive(TypeRef::INT16, TypeKind::Int16, "Int16", 2, 2)
      register_primitive(TypeRef::INT32, TypeKind::Int32, "Int32", 4, 4)
      register_primitive(TypeRef::INT64, TypeKind::Int64, "Int64", 8, 8)
      register_primitive(TypeRef::INT128, TypeKind::Int128, "Int128", 16, 16)
      register_primitive(TypeRef::UINT8, TypeKind::UInt8, "UInt8", 1, 1)
      register_primitive(TypeRef::UINT16, TypeKind::UInt16, "UInt16", 2, 2)
      register_primitive(TypeRef::UINT32, TypeKind::UInt32, "UInt32", 4, 4)
      register_primitive(TypeRef::UINT64, TypeKind::UInt64, "UInt64", 8, 8)
      register_primitive(TypeRef::UINT128, TypeKind::UInt128, "UInt128", 16, 16)
      register_primitive(TypeRef::FLOAT32, TypeKind::Float32, "Float32", 4, 4)
      register_primitive(TypeRef::FLOAT64, TypeKind::Float64, "Float64", 8, 8)
      register_primitive(TypeRef::CHAR, TypeKind::Char, "Char", 4, 4)
      register_primitive(TypeRef::STRING, TypeKind::Reference, "String", TARGET_POINTER_BYTES_U64, TARGET_POINTER_ALIGN_U32)
      register_primitive(TypeRef::SYMBOL, TypeKind::Symbol, "Symbol", 4, 4)
      register_primitive(TypeRef::POINTER, TypeKind::Pointer, "Pointer", TARGET_POINTER_BYTES_U64, TARGET_POINTER_ALIGN_U32)
    end

    private def register_primitive(ref : TypeRef, kind : TypeKind, name : String, size : UInt64, alignment : UInt32)
      type = Type.new(ref.id, kind, name, size, alignment)
      register_type(type)
    end

    def create_type(kind : TypeKind, name : String, size : UInt64, alignment : UInt32) : Type
      id = @next_type_id
      @next_type_id += 1
      type = Type.new(id, kind, name, size, alignment)
      register_type(type)
      type
    end

    # Create type with explicit id (for mapping HIR TypeRef to MIR Type)
    # If type already exists, return existing type
    def create_type_with_id(id : TypeId, kind : TypeKind, name : String, size : UInt64, alignment : UInt32) : Type
      # Return existing type if already registered
      if existing = get(id)
        return existing
      end
      type = Type.new(id, kind, name, size, alignment)
      register_type(type)
      type
    end

    def get(id : TypeId) : Type?
      @types_by_id[id]?
    end

    def get(ref : TypeRef) : Type?
      get(ref.id)
    end

    def get_by_name(name : String) : Type?
      @types_by_name[name]?
    end

    private def register_type(type : Type) : Nil
      @types << type
      @types_by_id[type.id] = type
      # Preserve the old reverse-scan get_by_name semantics: later type
      # registrations with the same name shadow earlier ones.
      @types_by_name[type.name] = type
    end

    # Human-readable layout snapshot for ABI sanity checks.
    # Includes size/alignment and field offsets for non-primitive types,
    # plus variant info for unions and element info for tuples/arrays.
    def layout_snapshot : String
      String.build do |io|
        @types.each do |type|
          next if type.kind.primitive?
          io << type.name << " (" << type.kind << "): size=" << type.size << " align=" << type.alignment << "\n"
          if fields = type.fields
            fields.each do |f|
              io << "  @" << f.name << " : type#" << f.type_ref.id << " @offset " << f.offset << "\n"
            end
          end
          if variants = type.variants
            variants.each do |v|
              io << "  variant " << v.name << " size=" << v.size << " align=" << v.alignment << "\n"
              if vf = v.fields
                vf.each do |f|
                  io << "    @" << f.name << " : type#" << f.type_ref.id << " @offset " << f.offset << "\n"
                end
              end
            end
          end
          if elem = type.element_type
            io << "  element " << elem.name << "\n"
          end
          if elems = type.element_types
            elems.each_with_index do |e, idx|
              io << "  element[" << idx << "] " << e.name << "\n"
            end
          end
        end
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TYPE REFERENCES (simplified for MIR - full types resolved)
  # ═══════════════════════════════════════════════════════════════════════════

  struct TypeRef
    getter id : TypeId

    def initialize(@id : TypeId)
    end

    # Primitive types (well-known IDs)
    VOID    = new(0_u32)
    NIL     = new(1_u32)
    BOOL    = new(2_u32)
    INT8    = new(3_u32)
    INT16   = new(4_u32)
    INT32   = new(5_u32)
    INT64   = new(6_u32)
    INT128  = new(7_u32)
    UINT8   = new(8_u32)
    UINT16  = new(9_u32)
    UINT32  = new(10_u32)
    UINT64  = new(11_u32)
    UINT128 = new(12_u32)
    FLOAT32 = new(13_u32)
    FLOAT64 = new(14_u32)
    CHAR    = new(15_u32)
    STRING  = new(16_u32)
    SYMBOL  = new(17_u32)
    POINTER = new(18_u32)  # Generic pointer type

    # Canonical HIR TypeRef id -> MIR (runtime) TypeRef id translation.
    #
    # HIR and MIR use DIFFERENT primitive id layouts (HIR places NIL at 16,
    # MIR places NIL at 1, which shifts BOOL..STRING by one), and user types
    # are offset by +20 when crossing into MIR. Any code that needs the runtime
    # type id of an HIR TypeRef (e.g. baking a type_id header literal) MUST go
    # through this method instead of using `hir_ref.id` directly, otherwise the
    # raw HIR id leaks into the runtime where MIR ids are expected.
    #
    # This is the single source of truth; HIRToMIRLowering#convert_type
    # delegates here so the two never drift.
    def self.from_hir(hir_type : HIR::TypeRef) : TypeRef
      return VOID if hir_type.null_ptr?
      hir_type_id = hir_type.id
      case hir_type_id
      when HIR::TypeRef::VOID.id    then VOID
      when HIR::TypeRef::BOOL.id    then BOOL
      when HIR::TypeRef::INT8.id    then INT8
      when HIR::TypeRef::INT16.id   then INT16
      when HIR::TypeRef::INT32.id   then INT32
      when HIR::TypeRef::INT64.id   then INT64
      when HIR::TypeRef::INT128.id  then INT128
      when HIR::TypeRef::UINT8.id   then UINT8
      when HIR::TypeRef::UINT16.id  then UINT16
      when HIR::TypeRef::UINT32.id  then UINT32
      when HIR::TypeRef::UINT64.id  then UINT64
      when HIR::TypeRef::UINT128.id then UINT128
      when HIR::TypeRef::FLOAT32.id then FLOAT32
      when HIR::TypeRef::FLOAT64.id then FLOAT64
      when HIR::TypeRef::CHAR.id    then CHAR
      when HIR::TypeRef::STRING.id  then STRING
      when HIR::TypeRef::NIL.id     then NIL
      when HIR::TypeRef::SYMBOL.id  then SYMBOL
      when HIR::TypeRef::POINTER.id then POINTER
      else
        # User-defined types: offset by primitive count.
        new(hir_type_id + 20_u32)
      end
    end

    def ==(other : TypeRef) : Bool
      @id == other.id
    end

    def hash(hasher)
      hasher = @id.hash(hasher)
      hasher
    end

    def to_s(io : IO) : Nil
      case self
      when VOID    then io << "void"
      when NIL     then io << "Nil"
      when BOOL    then io << "Bool"
      when INT8    then io << "Int8"
      when INT16   then io << "Int16"
      when INT32   then io << "Int32"
      when INT64   then io << "Int64"
      when INT128  then io << "Int128"
      when UINT8   then io << "UInt8"
      when UINT16  then io << "UInt16"
      when UINT32  then io << "UInt32"
      when UINT64  then io << "UInt64"
      when UINT128 then io << "UInt128"
      when FLOAT32 then io << "Float32"
      when FLOAT64 then io << "Float64"
      when CHAR    then io << "Char"
      when STRING  then io << "String"
      when SYMBOL  then io << "Symbol"
      when POINTER then io << "Pointer"
      else              io << "Type#" << @id
      end
    end

    def inspect(io : IO) : Nil
      to_s(io)
    end

    # TBAA: Type-Based Alias Analysis helpers
    # Primitive types never alias reference/struct types

    def primitive? : Bool
      case @id
      when 0_u32..17_u32  # VOID through SYMBOL
        # Note: STRING (16) and SYMBOL (17) are reference types in Crystal
        # but at MIR level they're primitives for TBAA purposes
        @id <= 15_u32 || @id == 17_u32  # Excludes STRING (16)
      else
        false
      end
    end

    def reference? : Bool
      # User-defined types (id >= 100) are typically reference types
      # STRING is a reference type
      @id == 16_u32 || @id >= 100_u32
    end

    def numeric? : Bool
      case @id
      when 3_u32..14_u32  # INT8 through FLOAT64
        true
      else
        false
      end
    end

    # Two types can alias if they're compatible for memory access
    # This is a conservative check - returns true if MAY alias
    def may_alias_type?(other : TypeRef) : Bool
      # Same type always may alias
      return true if @id == other.id

      # POINTER is the universal aliaser (like void* in C)
      return true if @id == 18_u32 || other.id == 18_u32

      # Primitives vs references: cannot alias
      # Int32* cannot point to the same memory as MyClass*
      if self.primitive? && other.reference?
        return false
      end
      if self.reference? && other.primitive?
        return false
      end

      # Different numeric types might alias through unions
      # Be conservative here
      true
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # VALUES - SSA Values (single assignment)
  # ═══════════════════════════════════════════════════════════════════════════

  abstract class Value
    getter id : ValueId
    getter type : TypeRef

    def initialize(@id : ValueId, @type : TypeRef)
    end

    abstract def to_s(io : IO) : Nil

    def inspect(io : IO) : Nil
      to_s(io)
    end

    # All operand value IDs this instruction uses
    def operands : Array(ValueId)
      [] of ValueId
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONSTANTS
  # ═══════════════════════════════════════════════════════════════════════════

  # Compile-time constant
  class Constant < Value
    getter value : Int64 | UInt64 | Float64 | Bool | Nil | String
    getter int_value : Int64
    getter uint_value : UInt64
    getter float_value : Float64
    getter bool_value : Bool
    getter string_value : String?

    property int_value : Int64 = 0_i64
    property uint_value : UInt64 = 0_u64
    property float_value : Float64 = 0.0
    property bool_value : Bool = false
    property string_value : String? = nil

    def initialize(id : ValueId, type : TypeRef, @value)
      super(id, type)
      sync_cached_value_fields
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = const "
      case @type
      when TypeRef::FLOAT32, TypeRef::FLOAT64
        io << @float_value
      when TypeRef::BOOL
        io << (@bool_value ? "true" : "false")
      when TypeRef::STRING
        if value = @string_value
          io << value.inspect
        else
          io << "nil"
        end
      when TypeRef::NIL, TypeRef::VOID
        io << "nil"
      when TypeRef::UINT8, TypeRef::UINT16, TypeRef::UINT32, TypeRef::UINT64, TypeRef::UINT128
        io << @uint_value
      else
        io << @int_value
      end
      io << " : " << @type
    end

    private def sync_cached_value_fields : Nil
      case v = @value
      when Int64
        @int_value = v
        @uint_value = v >= 0 ? v.to_u64 : 0_u64
      when UInt64
        @uint_value = v
        @int_value = v <= Int64::MAX.to_u64 ? v.to_i64 : 0_i64
      when Float64
        @float_value = v
      when Bool
        @bool_value = v
        @int_value = v ? 1_i64 : 0_i64
        @uint_value = v ? 1_u64 : 0_u64
      when String
        @string_value = v
      when Nil
        # Keep zero defaults for nil/void constants.
      end
    end
  end

  # Reference to undefined value (for phi incoming from unreachable blocks)
  class Undef < Value
    def initialize(id : ValueId, type : TypeRef)
      super(id, type)
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = undef : " << @type
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MEMORY OPERATIONS
  # ═══════════════════════════════════════════════════════════════════════════

  # Allocate memory with specific strategy
  class Alloc < Value
    getter strategy : MemoryStrategy
    getter alloc_type : TypeRef
    getter size : UInt64  # Static size in bytes (0 = compute from type)
    getter align : UInt32 # Alignment in bytes
    property no_alias : Bool = true

    def initialize(
      id : ValueId,
      type : TypeRef,
      @strategy : MemoryStrategy,
      @alloc_type : TypeRef,
      @size : UInt64 = 0_u64,
      @align : UInt32 = TARGET_POINTER_ALIGN_U32
    )
      super(id, type)
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = alloc " << @strategy
      io << " " << @alloc_type
      io << ", size=" << @size if @size > 0
      io << ", align=" << @align
      io << " [noalias]" if @no_alias
      io << " : " << @type
    end
  end

  # Free memory (for Slab strategy; no-op for others typically)
  class Free < Value
    getter ptr : ValueId
    getter strategy : MemoryStrategy

    def initialize(id : ValueId, @ptr : ValueId, @strategy : MemoryStrategy)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@ptr]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = free %" << @ptr << " (" << @strategy << ")"
    end
  end

  # Increment reference count (ARC)
  class RCIncrement < Value
    getter ptr : ValueId
    getter atomic : Bool

    def initialize(id : ValueId, @ptr : ValueId, @atomic : Bool = false)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@ptr]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = rc_inc"
      io << "_atomic" if @atomic
      io << " %" << @ptr
    end
  end

  # Decrement reference count (ARC) - may trigger destructor
  class RCDecrement < Value
    getter ptr : ValueId
    getter atomic : Bool
    getter destructor : FunctionId?

    def initialize(
      id : ValueId,
      @ptr : ValueId,
      @atomic : Bool = false,
      @destructor : FunctionId? = nil
    )
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@ptr]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = rc_dec"
      io << "_atomic" if @atomic
      io << " %" << @ptr
      if d = @destructor
        io << ", destructor=@" << d
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SYNCHRONIZATION PRIMITIVES
  # ═══════════════════════════════════════════════════════════════════════════

  # Memory ordering for atomic operations
  enum MemoryOrdering
    Relaxed    # No ordering constraints
    Acquire    # Loads after this see stores before matching Release
    Release    # Stores before this are visible after matching Acquire
    AcqRel     # Both Acquire and Release
    SeqCst     # Sequentially consistent (strongest)
  end

  # Atomic load
  class AtomicLoad < Value
    getter ptr : ValueId
    getter ordering : MemoryOrdering

    def initialize(id : ValueId, type : TypeRef, @ptr : ValueId, @ordering : MemoryOrdering = MemoryOrdering::SeqCst)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@ptr]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = atomic_load %" << @ptr << " " << @ordering << " : " << @type
    end
  end

  # Atomic store
  class AtomicStore < Value
    getter ptr : ValueId
    getter value : ValueId
    getter ordering : MemoryOrdering

    def initialize(id : ValueId, @ptr : ValueId, @value : ValueId, @ordering : MemoryOrdering = MemoryOrdering::SeqCst)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@ptr, @value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = atomic_store %" << @ptr << ", %" << @value << " " << @ordering
    end
  end

  # Atomic compare-and-swap (CAS)
  class AtomicCAS < Value
    getter ptr : ValueId
    getter expected : ValueId
    getter desired : ValueId
    getter success_ordering : MemoryOrdering
    getter failure_ordering : MemoryOrdering

    def initialize(
      id : ValueId,
      type : TypeRef,
      @ptr : ValueId,
      @expected : ValueId,
      @desired : ValueId,
      @success_ordering : MemoryOrdering = MemoryOrdering::SeqCst,
      @failure_ordering : MemoryOrdering = MemoryOrdering::SeqCst
    )
      super(id, type)  # Returns {old_value, success_bool}
    end

    def operands : Array(ValueId)
      [@ptr, @expected, @desired]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = cmpxchg %" << @ptr << ", %" << @expected << ", %" << @desired
      io << " " << @success_ordering << " " << @failure_ordering
    end
  end

  # Atomic read-modify-write operations
  enum AtomicRMWOp
    Xchg  # Exchange
    Add   # Add
    Sub   # Subtract
    And   # Bitwise AND
    Or    # Bitwise OR
    Xor   # Bitwise XOR
    Max   # Signed max
    Min   # Signed min
    UMax  # Unsigned max
    UMin  # Unsigned min
  end

  class AtomicRMW < Value
    getter op : AtomicRMWOp
    getter ptr : ValueId
    getter value : ValueId
    getter ordering : MemoryOrdering

    def initialize(
      id : ValueId,
      type : TypeRef,
      @op : AtomicRMWOp,
      @ptr : ValueId,
      @value : ValueId,
      @ordering : MemoryOrdering = MemoryOrdering::SeqCst
    )
      super(id, type)  # Returns old value
    end

    def operands : Array(ValueId)
      [@ptr, @value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = atomicrmw " << @op << " %" << @ptr << ", %" << @value << " " << @ordering
    end
  end

  # Memory fence (barrier)
  class Fence < Value
    getter ordering : MemoryOrdering

    def initialize(id : ValueId, @ordering : MemoryOrdering = MemoryOrdering::SeqCst)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [] of ValueId
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = fence " << @ordering
    end
  end

  # Mutex lock (runtime call)
  class MutexLock < Value
    getter mutex_ptr : ValueId

    def initialize(id : ValueId, @mutex_ptr : ValueId)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@mutex_ptr]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = mutex_lock %" << @mutex_ptr
    end
  end

  # Mutex unlock (runtime call)
  class MutexUnlock < Value
    getter mutex_ptr : ValueId

    def initialize(id : ValueId, @mutex_ptr : ValueId)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@mutex_ptr]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = mutex_unlock %" << @mutex_ptr
    end
  end

  # Mutex trylock (returns bool)
  class MutexTryLock < Value
    getter mutex_ptr : ValueId

    def initialize(id : ValueId, @mutex_ptr : ValueId)
      super(id, TypeRef::BOOL)
    end

    def operands : Array(ValueId)
      [@mutex_ptr]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = mutex_trylock %" << @mutex_ptr
    end
  end

  # Channel send
  class ChannelSend < Value
    getter channel_ptr : ValueId
    getter value : ValueId

    def initialize(id : ValueId, @channel_ptr : ValueId, @value : ValueId)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@channel_ptr, @value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = channel_send %" << @channel_ptr << ", %" << @value
    end
  end

  # Channel receive
  class ChannelReceive < Value
    getter channel_ptr : ValueId

    def initialize(id : ValueId, type : TypeRef, @channel_ptr : ValueId)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@channel_ptr]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = channel_receive %" << @channel_ptr << " : " << @type
    end
  end

  # Channel close
  class ChannelClose < Value
    getter channel_ptr : ValueId

    def initialize(id : ValueId, @channel_ptr : ValueId)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@channel_ptr]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = channel_close %" << @channel_ptr
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MEMORY ACCESS
  # ═══════════════════════════════════════════════════════════════════════════

  # Load from memory
  class Load < Value
    getter ptr : ValueId
    property no_alias : Bool = false

    def initialize(id : ValueId, type : TypeRef, @ptr : ValueId)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@ptr]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = load %" << @ptr << " : " << @type
    end
  end

  # Store to memory
  class Store < Value
    getter ptr : ValueId
    getter value : ValueId
    # Optional: the declared type of the destination field (when storing to a
    # class/struct ivar). Used by the LLVM backend to detect when a narrow
    # all-ref union (ptr) is stored into a wider non-all-ref union (struct),
    # so it can construct the proper tagged union struct.
    property field_type : TypeRef?

    def initialize(id : ValueId, @ptr : ValueId, @value : ValueId)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@ptr, @value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = store %" << @ptr << ", %" << @value
    end
  end

  # Memory copy — copies `size` bytes from src to dst (like llvm.memcpy)
  class MemCopy < Value
    getter dst : ValueId
    getter src : ValueId
    getter size : UInt64

    def initialize(id : ValueId, @dst : ValueId, @src : ValueId, @size : UInt64)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@dst, @src]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = memcopy %" << @dst << ", %" << @src << ", " << @size
    end
  end

  # Get element pointer (GEP) - compute address of field/element
  class GetElementPtr < Value
    getter base : ValueId
    getter indices : Array(UInt32)  # Field indices / array offsets
    getter base_type : TypeRef  # Type of base pointer (for struct GEP)

    def initialize(id : ValueId, type : TypeRef, @base : ValueId, @indices : Array(UInt32), @base_type : TypeRef = TypeRef::POINTER)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@base]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = gep %" << @base
      @indices.each { |idx| io << ", " << idx }
      io << " : " << @type
    end
  end

  # GEP with dynamic index - for pointer arithmetic with runtime offsets
  class GetElementPtrDynamic < Value
    getter base : ValueId
    getter index : ValueId  # Dynamic index (ValueId instead of UInt32)
    getter element_type : TypeRef  # Type of elements being indexed
    getter element_byte_size : UInt64  # 0 = use default from element_type

    # A' step (c→annotation): durable per-site provenance mark. Set ONCE during
    # HIR→MIR by the safe-set analysis: true iff this gep_dyn is the ADDRESS of a
    # Load/Store of its element type through the Array(C) @buffer-base chain
    # (buffer_value). A later behavior slice inline-stores ONLY at marked sites,
    # never re-deriving provenance by element type/name in LLVM (which is the
    # refuted type-driven over-firing). false = not an Array @buffer value access;
    # the gate that populates it is off by default and no lowering site reads it.
    property array_buffer_value : Bool = false

    # A' behavior: the inline byte stride (C.size) the behavior slice must use for
    # this gep, eligibility baked in (nil = legacy stride, do not rewrite). Set for
    # EVERY @buffer-derived gep_dyn of an inline_array_storage_eligible element C —
    # BOTH value-access geps (array_buffer_value) AND pointer-ARITHMETIC geps
    # (`@buffer + offset` feeding ptr_move/clear). emit_gep_dynamic reads ONLY this
    # to change the stride; array_buffer_value separately decides load/store memcpy
    # semantics. So the backend never re-derives @buffer provenance (no 2nd oracle).
    property array_buffer_element_stride : UInt64? = nil

    def initialize(id : ValueId, type : TypeRef, @base : ValueId, @index : ValueId, @element_type : TypeRef, @element_byte_size : UInt64 = 0_u64)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@base, @index]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = gep_dyn %" << @base << ", %" << @index << " : " << @type
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ARITHMETIC AND LOGIC
  # ═══════════════════════════════════════════════════════════════════════════

  enum BinOp
    Add
    Sub
    Mul
    Div
    Rem
    Shl
    Shr
    And
    Or
    Xor
    Eq
    Ne
    Lt
    Le
    Gt
    Ge

    def to_s : String
      case self
      when Add then "add"
      when Sub then "sub"
      when Mul then "mul"
      when Div then "div"
      when Rem then "rem"
      when Shl then "shl"
      when Shr then "shr"
      when And then "and"
      when Or  then "or"
      when Xor then "xor"
      when Eq  then "eq"
      when Ne  then "ne"
      when Lt  then "lt"
      when Le  then "le"
      when Gt  then "gt"
      else          "ge"  # Ge
      end
    end
  end

  class BinaryOp < Value
    getter op : BinOp
    getter left : ValueId
    getter right : ValueId

    def initialize(id : ValueId, type : TypeRef, @op : BinOp, @left : ValueId, @right : ValueId)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@left, @right]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = " << @op << " %" << @left << ", %" << @right << " : " << @type
    end
  end

  enum UnOp
    Neg
    Not
    BitNot

    def to_s : String
      case self
      when Neg then "neg"
      when Not then "not"
      else          "bitnot"  # BitNot
      end
    end
  end

  class UnaryOp < Value
    getter op : UnOp
    getter operand : ValueId

    def initialize(id : ValueId, type : TypeRef, @op : UnOp, @operand : ValueId)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@operand]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = " << @op << " %" << @operand << " : " << @type
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONVERSIONS
  # ═══════════════════════════════════════════════════════════════════════════

  enum CastKind
    Bitcast     # Same size, different type interpretation
    Trunc       # Integer truncation
    ZExt        # Zero extension
    SExt        # Sign extension
    FPToSI      # Float to signed int
    FPToUI      # Float to unsigned int
    SIToFP      # Signed int to float
    UIToFP      # Unsigned int to float
    FPTrunc     # Float truncation (double → float)
    FPExt       # Float extension (float → double)
    PtrToInt    # Pointer to integer
    IntToPtr    # Integer to pointer

    def to_s : String
      case self
      when Bitcast  then "bitcast"
      when Trunc    then "trunc"
      when ZExt     then "zext"
      when SExt     then "sext"
      when FPToSI   then "fptosi"
      when FPToUI   then "fptoui"
      when SIToFP   then "sitofp"
      when UIToFP   then "uitofp"
      when FPTrunc  then "fptrunc"
      when FPExt    then "fpext"
      when PtrToInt then "ptrtoint"
      else               "inttoptr"  # IntToPtr
      end
    end
  end

  class Cast < Value
    getter kind : CastKind
    getter value : ValueId

    def initialize(id : ValueId, type : TypeRef, @kind : CastKind, @value : ValueId)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = " << @kind << " %" << @value << " : " << @type
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONTROL FLOW (within block)
  # ═══════════════════════════════════════════════════════════════════════════

  # SSA Phi node - merges values from different control flow paths
  class Phi < Value
    # (BlockId, ValueId) - which value comes from which predecessor block
    getter incoming : Array(Tuple(BlockId, ValueId))
    getter incoming_blocks : Array(BlockId)
    getter incoming_values : Array(ValueId)

    def initialize(id : ValueId, type : TypeRef)
      super(id, type)
      @incoming = [] of Tuple(BlockId, ValueId)
      @incoming_blocks = [] of BlockId
      @incoming_values = [] of ValueId
    end

    # Add an incoming value from a predecessor block.
    # Named parameters are REQUIRED to prevent argument order bugs.
    # Correct:   phi.add_incoming(from: block_id, value: val_id)
    # Wrong:     phi.add_incoming(block_id, val_id)  # compile error
    def add_incoming(*, from block : BlockId, value : ValueId)
      @incoming << {block, value}
      @incoming_blocks << block
      @incoming_values << value
    end

    def incoming_size : Int32
      @incoming_blocks.size
    end

    def incoming_block_at(index : Int32) : BlockId
      @incoming_blocks.unsafe_fetch(index)
    end

    def incoming_value_at(index : Int32) : ValueId
      @incoming_values.unsafe_fetch(index)
    end

    def operands : Array(ValueId)
      @incoming_values.dup
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = phi "
      idx = 0
      while idx < @incoming_blocks.size
        block = @incoming_blocks.unsafe_fetch(idx)
        val = @incoming_values.unsafe_fetch(idx)
        io << ", " if idx > 0
        io << "[block." << block << ": %" << val << "]"
        idx += 1
      end
      io << " : " << @type
    end
  end

  # Select instruction (ternary: cond ? a : b)
  class Select < Value
    getter condition : ValueId
    getter then_value : ValueId
    getter else_value : ValueId

    def initialize(
      id : ValueId,
      type : TypeRef,
      @condition : ValueId,
      @then_value : ValueId,
      @else_value : ValueId
    )
      super(id, type)
    end

    def operands : Array(ValueId)
      [@condition, @then_value, @else_value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = select %" << @condition
      io << ", %" << @then_value << ", %" << @else_value
      io << " : " << @type
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DISCRIMINATED UNION OPERATIONS
  # ═══════════════════════════════════════════════════════════════════════════

  # Union variant descriptor for MIR-level union metadata
  record UnionVariantDescriptor,
    type_id : Int32,         # Discriminator value
    type_ref : TypeRef,      # Type of this variant
    full_name : String,      # Qualified type name
    size : Int32,            # Size in bytes
    alignment : Int32,       # Alignment requirement
    field_offsets : Hash(String, Int32)?  # For struct variants

  # Full union type descriptor
  record UnionDescriptor,
    name : String,                           # e.g., "Int32 | String | Nil"
    variants : Array(UnionVariantDescriptor),
    total_size : Int32,
    alignment : Int32,
    source_file : String? = nil,
    source_line : Int32? = nil do

    def header_size : Int32
      4  # i32 type_id discriminator
    end

    def payload_offset : Int32
      max_align = 8
      idx = 0
      while idx < variants.size
        alignment = variants.unsafe_fetch(idx).alignment
        max_align = alignment if alignment > max_align
        idx += 1
      end
      ((header_size + max_align - 1) // max_align) * max_align
    end

    def max_payload_size : Int32
      max_size = 0
      idx = 0
      while idx < variants.size
        size = variants.unsafe_fetch(idx).size
        max_size = size if size > max_size
        idx += 1
      end
      max_size
    end
  end

  record UnionDescriptorEntry,
    type_ref : TypeRef,
    descriptor : UnionDescriptor

  # Single authoritative union carrier classification shared by HIR->MIR
  # layout and LLVM lowering. Storage, header dispatch, and ownership are
  # deliberately distinct: a nullable raw Pointer is pointer-sized storage,
  # but it has neither an object type-id header nor managed ownership.
  enum UnionStorageKind
    Tagged
    RawHeaderPointer
    RawNullablePointer

    def raw_storage? : Bool
      self == RawHeaderPointer || self == RawNullablePointer
    end

    def runtime_header? : Bool
      self == RawHeaderPointer
    end

    def managed? : Bool
      self == RawHeaderPointer
    end
  end

  record UnionStorageEntry,
    type_ref : TypeRef,
    kind : UnionStorageKind

  def self.union_storage_from_entries(entries : ::Array(UnionStorageEntry)?, type_ref : TypeRef) : UnionStorageKind?
    return nil unless entries
    idx = 0
    while idx < entries.size
      entry = entries.unsafe_fetch(idx)
      return entry.kind if entry.type_ref == type_ref
      idx += 1
    end
    nil
  end

  def self.runtime_header_backed_type?(type : Type?) : Bool
    return false unless type
    kind = type.kind
    kind == TypeKind::Reference || kind == TypeKind::Array
  end

  def self.raw_pointer_union_variant?(type : Type?, name : String) : Bool
    name == "Pointer" || name.starts_with?("Pointer(") ||
      (!!type && type.kind == TypeKind::Pointer)
  end

  private def self.union_variant_name_runtime_header_backed?(type_registry : TypeRegistry, name : String) : Bool
    i = name.bytesize - 1
    while i > 0
      if name.byte_at(i) == ':'.ord && name.byte_at(i - 1) != ':'.ord
        base_name = name[(i + 1)..]
        return runtime_header_backed_type?(type_registry.get_by_name(base_name))
      end
      i -= 1
    end

    if paren_idx = name.index('(')
      generic_base = name[0...paren_idx]
      return runtime_header_backed_type?(type_registry.get_by_name(generic_base))
    end
    false
  end

  def self.union_storage_kind(type_registry : TypeRegistry, descriptor : UnionDescriptor) : UnionStorageKind
    saw_header = false
    saw_nil = false
    raw_pointer_count = 0
    variants = descriptor.variants
    idx = 0
    while idx < variants.size
      variant = variants.unsafe_fetch(idx)
      idx += 1

      if variant.type_ref == TypeRef::NIL
        saw_nil = true
        next
      end
      next if variant.type_ref == TypeRef::VOID

      type = type_registry.get(variant.type_ref)
      if raw_pointer_union_variant?(type, variant.full_name)
        # Descriptors are canonicalized before MIR registration. Count actual
        # variants: duplicate or distinct pointer arms are both ambiguous and
        # therefore remain tagged.
        raw_pointer_count += 1
      elsif runtime_header_backed_type?(type) ||
            (!type && union_variant_name_runtime_header_backed?(type_registry, variant.full_name))
        saw_header = true
      else
        return UnionStorageKind::Tagged
      end

      return UnionStorageKind::Tagged if saw_header && raw_pointer_count > 0
    end

    return UnionStorageKind::RawHeaderPointer if saw_header
    return UnionStorageKind::RawNullablePointer if saw_nil && raw_pointer_count == 1
    UnionStorageKind::Tagged
  end

  # Bootstrap-safe descriptor oracle. Generated stage2 has proven that reading
  # UnionDescriptor values from Hash(TypeRef, UnionDescriptor) can corrupt the
  # record even when key lookup succeeds; the append-only entry sidecar is the
  # authoritative read path.
  def self.union_descriptor_from_entries(entries : ::Array(UnionDescriptorEntry)?, type_ref : TypeRef) : UnionDescriptor?
    return nil unless entries
    idx = 0
    while idx < entries.size
      entry = entries.unsafe_fetch(idx)
      return entry.descriptor if entry.type_ref == type_ref
      idx += 1
    end
    nil
  end

  # Wrap value into union (sets discriminator + stores payload)
  class UnionWrap < Value
    getter value : ValueId          # Value to wrap
    getter variant_type_id : Int32  # Discriminator for this variant
    getter union_type : TypeRef     # Type of the resulting union

    def initialize(id : ValueId, type : TypeRef, @value : ValueId, @variant_type_id : Int32, @union_type : TypeRef)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = union_wrap %" << @value << " as variant " << @variant_type_id << " : " << @type
    end
  end

  # Unwrap value from union (extracts payload)
  class UnionUnwrap < Value
    getter union_value : ValueId    # Union to unwrap
    getter variant_type_id : Int32  # Expected discriminator
    getter safe : Bool              # true = return nil on mismatch; false = UB/trap

    def initialize(id : ValueId, type : TypeRef, @union_value : ValueId, @variant_type_id : Int32, @safe : Bool = false)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@union_value]
    end

    def to_s(io : IO) : Nil
      op = @safe ? "union_unwrap_safe" : "union_unwrap"
      io << "%" << @id << " = " << op << " %" << @union_value << " as variant " << @variant_type_id << " : " << @type
    end
  end

  # Get discriminator (type_id) from union
  class UnionTypeIdGet < Value
    getter union_value : ValueId

    def initialize(id : ValueId, @union_value : ValueId)
      super(id, TypeRef::INT32)
    end

    def operands : Array(ValueId)
      [@union_value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = union_type_id %" << @union_value << " : i32"
    end
  end

  # Check if union is specific variant
  class UnionIs < Value
    getter union_value : ValueId
    getter variant_type_id : Int32
    getter union_type : TypeRef

    def initialize(id : ValueId, @union_value : ValueId, @variant_type_id : Int32, @union_type : TypeRef = TypeRef::VOID)
      super(id, TypeRef::BOOL)
    end

    def operands : Array(ValueId)
      [@union_value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = union_is %" << @union_value << ", " << @variant_type_id << " : i1"
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Array Operations
  # ─────────────────────────────────────────────────────────────────────────────

  # Static array literal [1, 2, 3]
  # Creates stack-allocated array struct { i32 size, [N x T] data }
  class ArrayLiteral < Value
    getter element_type : TypeRef
    getter elements : Array(ValueId)
    property strategy : MemoryStrategy

    def initialize(id : ValueId, @element_type : TypeRef, @elements : Array(ValueId), @strategy : MemoryStrategy = MemoryStrategy::GC)
      super(id, TypeRef::POINTER)  # Returns ptr to array struct
    end

    def size : Int32
      @elements.size
    end

    def operands : Array(ValueId)
      @elements
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = array_literal " << @strategy << " ["
      @elements.join(io, ", ") { |e, o| o << "%" << e }
      io << "] : " << @element_type.id
    end
  end

  # Get array size
  class ArraySize < Value
    getter array_value : ValueId

    def initialize(id : ValueId, @array_value : ValueId)
      super(id, TypeRef::INT32)
    end

    def operands : Array(ValueId)
      [@array_value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = array_size %" << @array_value << " : i32"
    end
  end

  # Set array size (for in-place compaction)
  class ArraySetSize < Value
    getter array_value : ValueId
    getter size_value : ValueId

    def initialize(id : ValueId, @array_value : ValueId, @size_value : ValueId)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@array_value, @size_value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = array_set_size %" << @array_value << ", %" << @size_value
    end
  end

  # Allocate new empty array with given capacity
  class ArrayNew < Value
    getter capacity_value : ValueId
    getter element_type_ref : TypeRef

    def initialize(id : ValueId, @element_type_ref : TypeRef, @capacity_value : ValueId)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@capacity_value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = array_new capacity=%" << @capacity_value << " : " << @element_type_ref.id
    end
  end

  # Get array element by index
  class ArrayGet < Value
    getter array_value : ValueId
    getter index_value : ValueId
    getter element_type : TypeRef
    getter container_type : TypeRef?

    # C-narrow-b: durable mark set ONLY on a main-inlined `arr[i]` whose loaded value
    # is consumed exclusively by same-block local field reads, with no intervening
    # call / Array mutation / alias write / escape (the brutally-narrow v1 in
    # docs/abi_cnarrow_b_load_brief.md). A later behavior slice (gated, also requiring
    # A' on) reads fields directly from the inline @buffer[i] slot instead of
    # materializing the A' heap carrier. false = keep the carrier; set only under the
    # C-narrow-b preflight/behavior gate; no lowering reads it yet.
    property cnarrow_b_direct : Bool = false

    def initialize(id : ValueId, @element_type : TypeRef, @array_value : ValueId, @index_value : ValueId, @container_type : TypeRef? = nil)
      super(id, @element_type)
    end

    def operands : Array(ValueId)
      [@array_value, @index_value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = array_get %" << @array_value << "[%" << @index_value << "] : " << @element_type.id
    end
  end

  # Array element store: arr[index] = value
  class ArraySet < Value
    getter array_value : ValueId
    getter index_value : ValueId
    getter value_id : ValueId
    getter element_type : TypeRef
    getter container_type : TypeRef?

    def initialize(id : ValueId, @element_type : TypeRef, @array_value : ValueId, @index_value : ValueId, @value_id : ValueId, @container_type : TypeRef? = nil)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [@array_value, @index_value, @value_id]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = array_set %" << @array_value << "[%" << @index_value << "] = %" << @value_id << " : " << @element_type.id
    end
  end

  # String interpolation "Hello #{x}!"
  class StringInterpolation < Value
    getter parts : Array(ValueId)
    getter part_types : Array(TypeRef)?

    def initialize(id : ValueId, @parts : Array(ValueId), @part_types : Array(TypeRef)? = nil)
      super(id, TypeRef::STRING)
    end

    def operands : Array(ValueId)
      @parts
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = string_interpolation ["
      @parts.join(io, ", ") { |p, o| o << "%" << p }
      io << "]"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GLOBAL VARIABLE ACCESS
  # ═══════════════════════════════════════════════════════════════════════════

  # Load from global variable (class var)
  class GlobalLoad < Value
    getter global_name : String

    def initialize(id : ValueId, type : TypeRef, @global_name : String)
      super(id, type)
    end

    def operands : Array(ValueId)
      [] of ValueId
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = global_load @" << @global_name << " : " << @type
    end
  end

  # Store to global variable (class var)
  class GlobalStore < Value
    getter global_name : String
    getter value : ValueId

    def initialize(id : ValueId, type : TypeRef, @global_name : String, @value : ValueId)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@value]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = global_store @" << @global_name << ", %" << @value
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FUNCTION CALLS
  # ═══════════════════════════════════════════════════════════════════════════

  # Direct function call
  class Call < Value
    getter callee : FunctionId
    getter args : Array(ValueId)
    property materialization_tx_id : String? = nil
    property materialization_contract : MaterializationContractFacts? = nil
    # Optional semantic identity transport. T1b0 keeps this metadata inert:
    # MIR/LLVM selection and materialization still use their existing paths.
    getter resolution_handoff : Adamas::Compiler::Semantic::CallResolutionHandoff?

    # A' mini-AbiFacts: durable per-site classification of an Array(C) @buffer bulk
    # op that lowers as a Call to a shared `Pointer(C)#` body (clear / move_from /
    # copy_from / …) inside a monomorphic Array(C)# body. nil = not an Array bulk op.
    # A later behavior slice rewrites ONLY covered call sites to a direct
    # inline-stride op; set only under the facts gate; no lowering reads it yet.
    property array_bulk_op : ArrayBulkOpKind? = nil

    # A' behavior: inline payload stride (C.size), eligibility baked in (0 = do not
    # rewrite); and the LOGICAL element count so the rewrite builds the new byte
    # count as `logical_count * stride`. See ExternCall for the cases. nil count on
    # an otherwise-covered op → fail-closed (Uncovered).
    property array_bulk_stride : UInt32 = 0_u32
    property array_bulk_logical_count : ValueId? = nil

    # C-narrow-a placement: durable shape+eligibility candidate mark on a struct
    # ALLOCATOR call (`T.new$...`) whose result is the fresh sole-use value of a
    # monomorphic `Array(T)#<<`/`#push`, where T is inline_array_storage_eligible +
    # semantic_recursive_pod. A later behavior slice (gated, also requiring A' on)
    # replaces this call-site with a stack alloc + in-place initialize (Shape-C),
    # dropping the transient heap allocation. nil/false = not a placement candidate;
    # set only under the candidate gate; no lowering reads it yet.
    property cnarrow_a_candidate : Bool = false

    def initialize(
      id : ValueId,
      type : TypeRef,
      @callee : FunctionId,
      @args : Array(ValueId),
      @materialization_tx_id : String? = nil,
      @materialization_contract : MaterializationContractFacts? = nil,
      @resolution_handoff : Adamas::Compiler::Semantic::CallResolutionHandoff? = nil,
    )
      super(id, type)
    end

    def operands : Array(ValueId)
      @args.dup
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = call @" << @callee << "("
      @args.each_with_index do |arg, idx|
        io << ", " if idx > 0
        io << "%" << arg
      end
      io << ") : " << @type
    end
  end

  # External/runtime function call by name
  class ExternCall < Value
    getter extern_name : String
    getter args : Array(ValueId)
    property materialization_tx_id : String? = nil
    property materialization_contract : MaterializationContractFacts? = nil

    # A' mini-AbiFacts: durable per-site classification of an Array(C) @buffer bulk
    # op (memmove/memcpy/memset/malloc/realloc) found inside a monomorphic Array(C)#
    # body. nil = not an Array bulk op (leave alone). A later behavior slice reads
    # this to rewrite ONLY covered sites to the inline element stride — never
    # re-deriving the classification in LLVM. Set only under the facts gate.
    property array_bulk_op : ArrayBulkOpKind? = nil

    # A' behavior: the inline payload stride (C.size), eligibility baked in (0 = do
    # not rewrite); and the LOGICAL element count so the behavior slice builds the
    # new byte count as `logical_count * stride` (GPT: build new, the old `count*CONST`
    # / explicit elem_size const is shape-proof only). Cases:
    #   __adamas_ptr_move/ptr_copy(dest,src,count,elem_size) → logical_count = count arg.
    #   llvm.memmove/memcpy/memset(...,bytes) bytes=count*CONST → non-const operand.
    #   malloc/realloc(size) size=cap*CONST → non-const operand.
    # nil count on an otherwise-covered op → fail-closed (Uncovered).
    property array_bulk_stride : UInt32 = 0_u32
    property array_bulk_logical_count : ValueId? = nil

    def initialize(
      id : ValueId,
      type : TypeRef,
      @extern_name : String,
      @args : Array(ValueId),
      @materialization_tx_id : String? = nil,
      @materialization_contract : MaterializationContractFacts? = nil,
    )
      super(id, type)
    end

    def operands : Array(ValueId)
      @args.dup
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = extern_call @" << @extern_name << "("
      @args.each_with_index do |arg, idx|
        io << ", " if idx > 0
        io << "%" << arg
      end
      io << ") : " << @type
    end
  end

  # Get address of a value (pointerof)
  class AddressOf < Value
    getter operand : ValueId

    def initialize(id : ValueId, type : TypeRef, @operand : ValueId)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@operand]
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = addressof %" << @operand << " : " << @type
    end
  end

  # Indirect call through function pointer
  class IndirectCall < Value
    getter callee_ptr : ValueId
    getter args : Array(ValueId)
    getter unwrap_union_args : Bool

    def initialize(id : ValueId, type : TypeRef, @callee_ptr : ValueId, @args : Array(ValueId), @unwrap_union_args : Bool = true)
      super(id, type)
    end

    def operands : Array(ValueId)
      [@callee_ptr] + @args
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = call_indirect %" << @callee_ptr << "("
      @args.each_with_index do |arg, idx|
        io << ", " if idx > 0
        io << "%" << arg
      end
      io << ")"
      io << " preserve_unions" unless @unwrap_union_args
      io << " : " << @type
    end
  end

  # Exception handling - try block begin (inline setjmp)
  # Returns 0 for normal path, non-zero for exception path
  class TryBegin < Value
    def initialize(id : ValueId)
      super(id, TypeRef::INT32)
    end

    def operands : Array(ValueId)
      [] of ValueId
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = try_begin : i32"
    end
  end

  # Exception handling - try block end (clear exception handler)
  class TryEnd < Value
    def initialize(id : ValueId)
      super(id, TypeRef::VOID)
    end

    def operands : Array(ValueId)
      [] of ValueId
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = try_end"
    end
  end

  # Raw function pointer — produces ptr to a named function (for C callbacks)
  class FuncPointer < Value
    getter func_name : String

    def initialize(id : ValueId, type : TypeRef, @func_name : String)
      super(id, type)
    end

    def operands : Array(ValueId)
      [] of ValueId
    end

    def to_s(io : IO) : Nil
      io << "%" << @id << " = func_pointer @" << @func_name << " : ptr"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TERMINATORS - End a basic block
  # ═══════════════════════════════════════════════════════════════════════════

  abstract class Terminator
    abstract def to_s(io : IO) : Nil
    abstract def successors : Array(BlockId)

    def inspect(io : IO) : Nil
      to_s(io)
    end
  end

  # Return from function
  class Return < Terminator
    getter value : ValueId?

    def initialize(@value : ValueId? = nil)
    end

    def successors : Array(BlockId)
      [] of BlockId
    end

    def to_s(io : IO) : Nil
      io << "ret"
      if v = @value
        io << " %" << v
      end
    end
  end

  # Unconditional jump
  class Jump < Terminator
    getter target : BlockId

    def initialize(@target : BlockId)
    end

    def successors : Array(BlockId)
      [@target]
    end

    def to_s(io : IO) : Nil
      io << "jump block." << @target
    end
  end

  # Conditional branch
  class Branch < Terminator
    getter condition : ValueId
    getter then_block : BlockId
    getter else_block : BlockId

    def initialize(@condition : ValueId, @then_block : BlockId, @else_block : BlockId)
    end

    def successors : Array(BlockId)
      [@then_block, @else_block]
    end

    def to_s(io : IO) : Nil
      io << "br %" << @condition
      io << ", block." << @then_block
      io << ", block." << @else_block
    end
  end

  # Multi-way branch (switch)
  class Switch < Terminator
    getter value : ValueId
    getter cases : Array(Tuple(Int64, BlockId))  # value → block
    getter default_block : BlockId

    def initialize(@value : ValueId, @cases : Array(Tuple(Int64, BlockId)), @default_block : BlockId)
    end

    def successors : Array(BlockId)
      successors = Array(BlockId).new(@cases.size + 1)
      idx = 0
      while idx < @cases.size
        successors << @cases.unsafe_fetch(idx)[1]
        idx += 1
      end
      successors << @default_block
      successors
    end

    def to_s(io : IO) : Nil
      io << "switch %" << @value << " ["
      @cases.each_with_index do |(val, block), idx|
        io << ", " if idx > 0
        io << val << " → block." << block
      end
      io << "] default block." << @default_block
    end
  end

  # Unreachable (after noreturn calls like raise)
  class Unreachable < Terminator
    def successors : Array(BlockId)
      [] of BlockId
    end

    def to_s(io : IO) : Nil
      io << "unreachable"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BASIC BLOCK
  # ═══════════════════════════════════════════════════════════════════════════

  class BasicBlock
    getter id : BlockId
    getter instructions : ::Array(Value)
    property terminator : Terminator

    # Predecessor blocks (computed)
    property predecessors : ::Array(BlockId)

    def initialize(@id : BlockId)
      @instructions = [] of Value
      @terminator = Unreachable.new
      @predecessors = [] of BlockId
    end

    def add(instruction : Value)
      @instructions << instruction
    end

    # Insert phi node at beginning
    def add_phi(phi : Phi)
      # Phi nodes must come first
      phi_count = @instructions.count { |i| i.is_a?(Phi) }
      @instructions.insert(phi_count, phi.as(Value))
    end

    def to_s(io : IO) : Nil
      io << "block." << @id << ":"
      if !@predecessors.empty?
        io << "  ; preds: "
        @predecessors.each_with_index do |pred, idx|
          io << ", " if idx > 0
          io << "block." << pred
        end
      end
      io << "\n"
      @instructions.each do |inst|
        io << "  "
        inst.to_s(io)
        io << "\n"
      end
      io << "  "
      @terminator.to_s(io)
      io << "\n"
    end

    def inspect(io : IO) : Nil
      to_s(io)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FUNCTION
  # ═══════════════════════════════════════════════════════════════════════════

  struct Parameter
    getter index : UInt32
    getter name : String
    getter type : TypeRef
    # Default literal value for optional params (e.g., "10" for base : Int = 10)
    getter default_value : String?

    def initialize(@index : UInt32, @name : String, @type : TypeRef, @default_value : String? = nil)
    end
  end

  # Source location for debug info
  struct SourceLocation
    getter file : String
    getter line : Int32
    getter column : Int32

    def initialize(@file, @line, @column = 0)
    end
  end

  record DebugLocalBinding,
    slot_id : ValueId,
    value_id : ValueId,
    location : SourceLocation,
    lexical_scope_id : UInt32? = nil

  class Function
    @id : FunctionId
    @name : String
    @params : ::Array(Parameter)
    @return_type : TypeRef
    @blocks : ::Array(BasicBlock)
    @entry_block : BlockId
    @source_location : SourceLocation?
    @value_locations : ::Hash(ValueId, SourceLocation)
    @value_lexical_scopes : ::Hash(ValueId, UInt32)
    @debug_local_names : ::Hash(ValueId, String)
    @debug_local_bindings : ::Array(DebugLocalBinding)
    @debug_scope_parent : ::Hash(UInt32, UInt32?)
    @debug_scope_opening : ::Hash(UInt32, SourceLocation)
    @debug_scope_closing : ::Hash(UInt32, SourceLocation)
    @slab_frame : Bool

    getter id : FunctionId
    getter name : String
    getter params : ::Array(Parameter)
    getter return_type : TypeRef
    getter blocks : ::Array(BasicBlock)
    getter entry_block : BlockId
    property source_location : SourceLocation?
    property slab_frame : Bool = false

    @next_value_id : ValueId = 0_u32
    @next_block_id : BlockId = 0_u32
    @block_map : ::Hash(BlockId, BasicBlock)

    def initialize(@id : FunctionId, @name : String, @return_type : TypeRef)
      @params = [] of Parameter
      @blocks = [] of BasicBlock
      @block_map = {} of BlockId => BasicBlock
      @source_location = nil
      @value_locations = {} of ValueId => SourceLocation
      @value_lexical_scopes = {} of ValueId => UInt32
      @debug_local_names = {} of ValueId => String
      @debug_local_bindings = [] of DebugLocalBinding
      @debug_scope_parent = {} of UInt32 => UInt32?
      @debug_scope_opening = {} of UInt32 => SourceLocation
      @debug_scope_closing = {} of UInt32 => SourceLocation
      @slab_frame = false

      # Create entry block
      @entry_block = create_block
    end

    def add_param(name : String, type : TypeRef, default_value : String? = nil) : UInt32
      idx = @params.size.to_u32
      @params << Parameter.new(idx, name, type, default_value)
      # Reserve value IDs so instruction IDs don't clash with param indices
      @next_value_id = @params.size.to_u32
      idx
    end

    def next_value_id : ValueId
      id = @next_value_id
      @next_value_id += 1
      id
    end

    def record_value_location(value_id : ValueId, location : SourceLocation) : Nil
      @value_locations[value_id] = location
    end

    def record_value_lexical_scope(value_id : ValueId, hir_scope_id : UInt32) : Nil
      @value_lexical_scopes[value_id] = hir_scope_id
    end

    def value_location(value_id : ValueId) : SourceLocation?
      @value_locations[value_id]?
    end

    def value_lexical_scope(value_id : ValueId) : UInt32?
      @value_lexical_scopes[value_id]?
    end

    def record_debug_local_name(value_id : ValueId, name : String) : Nil
      @debug_local_names[value_id] = name
    end

    def debug_local_name(value_id : ValueId) : String?
      @debug_local_names[value_id]?
    end

    def debug_local_bindings : ::Array(DebugLocalBinding)
      @debug_local_bindings
    end

    def record_debug_local_binding(slot_id : ValueId, value_id : ValueId, location : SourceLocation, lexical_scope_id : UInt32? = nil) : Nil
      if last = @debug_local_bindings.last?
        return if last.slot_id == slot_id && last.value_id == value_id && last.location == location && last.lexical_scope_id == lexical_scope_id
      end
      @debug_local_bindings << DebugLocalBinding.new(slot_id, value_id, location, lexical_scope_id)
    end

    def record_debug_scope_metadata(scope_id : UInt32, parent_id : UInt32?, opening : SourceLocation) : Nil
      @debug_scope_parent[scope_id] = parent_id
      @debug_scope_opening[scope_id] = opening
    end

    def record_debug_scope_closing(scope_id : UInt32, closing : SourceLocation) : Nil
      @debug_scope_closing[scope_id] = closing
    end

    def debug_scope_parent?(scope_id : UInt32) : UInt32?
      @debug_scope_parent[scope_id]?
    end

    def debug_scope_opening?(scope_id : UInt32) : SourceLocation?
      @debug_scope_opening[scope_id]?
    end

    def debug_scope_closing?(scope_id : UInt32) : SourceLocation?
      @debug_scope_closing[scope_id]?
    end

    def create_block : BlockId
      id = @next_block_id
      @next_block_id += 1
      block = BasicBlock.new(id)
      @blocks << block
      @block_map[id] = block
      id
    end

    def get_block(id : BlockId) : BasicBlock
      if id < @blocks.size
        block = @blocks.unsafe_fetch(id)
        return block if block.id == id
      end

      @blocks.each do |block|
        return block if block.id == id
      end

      @block_map[id]
    end

    def get_block?(id : BlockId) : BasicBlock?
      if id < @blocks.size
        block = @blocks.unsafe_fetch(id)
        return block if block.id == id
      end

      @blocks.each do |block|
        return block if block.id == id
      end

      @block_map[id]?
    end

    # Compute predecessor information for all blocks
    def compute_predecessors
      @blocks.each { |b| b.predecessors.clear }

      @blocks.each do |block|
        succ_ids = block.terminator.successors
        if succ_ids.size > 1
          seen = ::Set(BlockId).new
          succ_ids.each do |succ_id|
            next if seen.includes?(succ_id)
            seen << succ_id
            if succ = @block_map[succ_id]?
              succ.predecessors << block.id
            end
          end
          next
        end

        succ_ids.each do |succ_id|
          if succ = @block_map[succ_id]?
            succ.predecessors << block.id
          end
        end
      end
    end

    def to_s(io : IO) : Nil
      io << "func @" << @name << "("
      @params.each_with_index do |param, idx|
        io << ", " if idx > 0
        io << "%" << param.index << ": " << param.type
      end
      io << ") -> " << @return_type << " {\n"

      @blocks.each do |block|
        block.to_s(io)
      end

      io << "}\n"
    end

    def inspect(io : IO) : Nil
      to_s(io)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MODULE
  # ═══════════════════════════════════════════════════════════════════════════

  # Global variable info
  record GlobalVar,
    name : String,
    type : TypeRef,
    initial_value : Int64?,
    debug_name : String? = nil,
    source_location : SourceLocation? = nil

  class Module
    getter name : String
    getter functions : ::Array(Function)
    getter type_registry : TypeRegistry
    getter globals : ::Array(GlobalVar)
    getter extern_globals : ::Hash(String, TypeRef)
    getter union_descriptors : ::Hash(TypeRef, UnionDescriptor)
    getter union_descriptor_entries : ::Array(UnionDescriptorEntry)
    getter union_storage_entries : ::Array(UnionStorageEntry)
    getter module_type_refs : ::Set(TypeRef)
    property source_file : String?
    # Set during HIR->MIR lowering when any allocation is assigned MemoryStrategy::GC.
    # The entry point reads this to decide whether to emit GC_init (hybrid memory
    # model): pure stack/ARC programs never touch the Boehm collector and skip it.
    property uses_gc : Bool = false

    @next_function_id : FunctionId = 0_u32
    @function_map : ::Hash(String, Function)
    # Symbol table: maps symbol name -> integer ID for :symbol_to_s lookup
    getter symbol_names : ::Array(String)
    @symbol_name_to_id : ::Hash(String, Int32)

    def initialize(@name : String = "main")
      @functions = [] of Function
      @function_map = {} of String => Function
      @type_registry = TypeRegistry.new
      @globals = [] of GlobalVar
      @extern_globals = {} of String => TypeRef
      @union_descriptors = {} of TypeRef => UnionDescriptor
      @union_descriptor_entries = [] of UnionDescriptorEntry
      @union_storage_entries = [] of UnionStorageEntry
      @module_type_refs = ::Set(TypeRef).new
      @symbol_names = [] of String
      @symbol_name_to_id = {} of String => Int32
    end

    # Register a symbol name and return its integer ID.
    def intern_symbol(name : String) : Int32
      if id = @symbol_name_to_id[name]?
        id
      else
        id = @symbol_names.size.to_i32
        @symbol_names << name
        @symbol_name_to_id[name] = id
        id
      end
    end

    # Register a union type with full descriptor for debug info
    def register_union(type_ref : TypeRef, descriptor : UnionDescriptor)
      @union_descriptors[type_ref] = descriptor
      idx = 0
      while idx < @union_descriptor_entries.size
        entry = @union_descriptor_entries.unsafe_fetch(idx)
        if entry.type_ref == type_ref
          @union_descriptor_entries[idx] = UnionDescriptorEntry.new(type_ref, descriptor)
          set_union_storage_kind(type_ref, Adamas::MIR.union_storage_kind(@type_registry, descriptor))
          return
        end
        idx += 1
      end
      @union_descriptor_entries << UnionDescriptorEntry.new(type_ref, descriptor)
      set_union_storage_kind(type_ref, Adamas::MIR.union_storage_kind(@type_registry, descriptor))
    end

    # Get union descriptor by type ref
    def get_union_descriptor(type_ref : TypeRef) : UnionDescriptor?
      Adamas::MIR.union_descriptor_from_entries(@union_descriptor_entries, type_ref)
    end

    def get_union_storage_kind(type_ref : TypeRef) : UnionStorageKind
      Adamas::MIR.union_storage_from_entries(@union_storage_entries, type_ref) || UnionStorageKind::Tagged
    end

    # Refresh only after all variant types for the phase are registered. LLVM
    # consumes this stable snapshot instead of reclassifying against a registry
    # that can still grow during HIR lowering.
    def refresh_union_storage_kinds : Nil
      idx = 0
      while idx < @union_descriptor_entries.size
        entry = @union_descriptor_entries.unsafe_fetch(idx)
        kind = Adamas::MIR.union_storage_kind(@type_registry, entry.descriptor)
        set_union_storage_kind(entry.type_ref, kind)
        if kind.raw_storage?
          if union_type = @type_registry.get(entry.type_ref)
            if union_type.kind.union?
              union_type.size = TARGET_POINTER_BYTES_U64
              union_type.alignment = TARGET_POINTER_ALIGN_U32
            end
          end
        end
        idx += 1
      end
    end

    private def set_union_storage_kind(type_ref : TypeRef, kind : UnionStorageKind) : Nil
      idx = 0
      while idx < @union_storage_entries.size
        entry = @union_storage_entries.unsafe_fetch(idx)
        if entry.type_ref == type_ref
          @union_storage_entries[idx] = UnionStorageEntry.new(type_ref, kind)
          return
        end
        idx += 1
      end
      @union_storage_entries << UnionStorageEntry.new(type_ref, kind)
    end

    # Register a TypeRef as a module runtime value type.
    # Module literals use singleton globals keyed by this set in LLVM lowering.
    def register_module_type(type_ref : TypeRef)
      @module_type_refs.add(type_ref)
    end

    def module_type?(type_ref : TypeRef) : Bool
      @module_type_refs.includes?(type_ref)
    end

    def add_global(
      name : String,
      type : TypeRef,
      initial_value : Int64? = nil,
      debug_name : String? = nil,
      source_location : SourceLocation? = nil
    )
      @globals << GlobalVar.new(name, type, initial_value, debug_name, source_location)
    end

    def add_extern_global(name : String, type : TypeRef)
      @extern_globals[name] = type
    end

    def types : Array(Type)
      @type_registry.types
    end

    def create_function(name : String, return_type : TypeRef) : Function
      id = @next_function_id
      @next_function_id += 1
      func = Function.new(id, name, return_type)
      @functions << func
      @function_map[name] = func
      func
    end

    def get_function(name : String) : Function?
      @function_map[name]?
    end

    def remove_function(name : String)
      if func = @function_map[name]?
        @functions.delete(func)
        @function_map.delete(name)
      end
    end

    def to_s(io : IO) : Nil
      io << "; MIR Module: " << @name << "\n\n"
      @functions.each do |func|
        func.to_s(io)
        io << "\n"
      end
    end

    def inspect(io : IO) : Nil
      to_s(io)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BUILDER - Helper for constructing MIR
  # ═══════════════════════════════════════════════════════════════════════════

  class Builder
    getter function : Function
    property current_block : BlockId

    def initialize(@function : Function)
      @current_block = @function.entry_block
    end

    private def block : BasicBlock
      @function.get_block(@current_block)
    end

    def emit(value : Value) : ValueId
      block.add(value)
      value.id
    end

    def next_id : ValueId
      @function.next_value_id
    end

    # Constants
    def const_int(value : Int64, type : TypeRef = TypeRef::INT64) : ValueId
      constant = Constant.new(@function.next_value_id, type, value)
      constant.int_value = value
      constant.uint_value = value >= 0 ? value.to_u64 : 0_u64
      emit(constant)
    end

    def const_uint(value : UInt64, type : TypeRef = TypeRef::UINT64) : ValueId
      constant = Constant.new(@function.next_value_id, type, value)
      constant.uint_value = value
      emit(constant)
    end

    def const_float(value : Float64, type : TypeRef = TypeRef::FLOAT64) : ValueId
      constant = Constant.new(@function.next_value_id, type, value)
      constant.float_value = value
      emit(constant)
    end

    def const_bool(value : Bool) : ValueId
      constant = Constant.new(@function.next_value_id, TypeRef::BOOL, value)
      constant.bool_value = value
      constant.int_value = value ? 1_i64 : 0_i64
      constant.uint_value = value ? 1_u64 : 0_u64
      emit(constant)
    end

    def const_nil : ValueId
      emit(Constant.new(@function.next_value_id, TypeRef::NIL, nil))
    end

    # Nil with explicit type (for typed nil pointers)
    def const_nil_typed(type : TypeRef) : ValueId
      emit(Constant.new(@function.next_value_id, type, nil))
    end

    def const_string(value : String) : ValueId
      constant = Constant.new(@function.next_value_id, TypeRef::STRING, value)
      constant.string_value = value
      emit(constant)
    end

    # Memory operations
    def alloc(strategy : MemoryStrategy, alloc_type : TypeRef, size : UInt64 = 0_u64, align : UInt32 = TARGET_POINTER_ALIGN_U32) : ValueId
      # Result type is pointer to alloc_type
      alloc = Alloc.new(@function.next_value_id, TypeRef::POINTER, strategy, alloc_type, size, align)
      alloc.no_alias = true
      emit(alloc)
    end

    def free(ptr : ValueId, strategy : MemoryStrategy) : ValueId
      emit(Free.new(@function.next_value_id, ptr, strategy))
    end

    def rc_inc(ptr : ValueId, atomic : Bool = false) : ValueId
      emit(RCIncrement.new(@function.next_value_id, ptr, atomic))
    end

    def rc_dec(ptr : ValueId, atomic : Bool = false, destructor : FunctionId? = nil) : ValueId
      emit(RCDecrement.new(@function.next_value_id, ptr, atomic, destructor))
    end

    # Synchronization primitives
    def atomic_load(ptr : ValueId, type : TypeRef, ordering : MemoryOrdering = MemoryOrdering::SeqCst) : ValueId
      emit(AtomicLoad.new(@function.next_value_id, type, ptr, ordering))
    end

    def atomic_store(ptr : ValueId, value : ValueId, ordering : MemoryOrdering = MemoryOrdering::SeqCst) : ValueId
      emit(AtomicStore.new(@function.next_value_id, ptr, value, ordering))
    end

    def atomic_cas(ptr : ValueId, expected : ValueId, desired : ValueId, type : TypeRef,
                   success_ordering : MemoryOrdering = MemoryOrdering::SeqCst,
                   failure_ordering : MemoryOrdering = MemoryOrdering::SeqCst) : ValueId
      emit(AtomicCAS.new(@function.next_value_id, type, ptr, expected, desired, success_ordering, failure_ordering))
    end

    def atomic_rmw(op : AtomicRMWOp, ptr : ValueId, value : ValueId, type : TypeRef,
                   ordering : MemoryOrdering = MemoryOrdering::SeqCst) : ValueId
      emit(AtomicRMW.new(@function.next_value_id, type, op, ptr, value, ordering))
    end

    def fence(ordering : MemoryOrdering = MemoryOrdering::SeqCst) : ValueId
      emit(Fence.new(@function.next_value_id, ordering))
    end

    # Resolve a ValueId to its integer constant value if it was produced by a
    # Constant instruction. Returns nil for non-constant values. Used by atomic
    # primitive lowering to extract LLVM enum values (op, ordering) from i32
    # literals produced by HIR-level symbol→enum conversion.
    def find_constant_int(id : ValueId) : Int64?
      @function.blocks.each do |blk|
        blk.instructions.each do |inst|
          if inst.id == id
            return inst.is_a?(Constant) ? inst.int_value : nil
          end
        end
      end
      nil
    end

    # Like find_constant_int but returns the Constant instruction so callers can
    # inspect its type (e.g. distinguish an Int enum value from an interned
    # Symbol id, which share the same int_value slot).
    def find_constant(id : ValueId) : Constant?
      @function.blocks.each do |blk|
        blk.instructions.each do |inst|
          if inst.id == id
            return inst.as(Constant) if inst.is_a?(Constant)
            return nil
          end
        end
      end
      nil
    end

    def mutex_lock(mutex_ptr : ValueId) : ValueId
      emit(MutexLock.new(@function.next_value_id, mutex_ptr))
    end

    def mutex_unlock(mutex_ptr : ValueId) : ValueId
      emit(MutexUnlock.new(@function.next_value_id, mutex_ptr))
    end

    def mutex_trylock(mutex_ptr : ValueId) : ValueId
      emit(MutexTryLock.new(@function.next_value_id, mutex_ptr))
    end

    def channel_send(channel_ptr : ValueId, value : ValueId) : ValueId
      emit(ChannelSend.new(@function.next_value_id, channel_ptr, value))
    end

    def channel_receive(channel_ptr : ValueId, type : TypeRef) : ValueId
      emit(ChannelReceive.new(@function.next_value_id, type, channel_ptr))
    end

    def channel_close(channel_ptr : ValueId) : ValueId
      emit(ChannelClose.new(@function.next_value_id, channel_ptr))
    end

    def load(ptr : ValueId, type : TypeRef) : ValueId
      emit(Load.new(@function.next_value_id, type, ptr))
    end

    def store(ptr : ValueId, value : ValueId) : ValueId
      emit(Store.new(@function.next_value_id, ptr, value))
    end

    def memcopy(dst : ValueId, src : ValueId, size : UInt64) : ValueId
      emit(MemCopy.new(@function.next_value_id, dst, src, size))
    end

    def global_load(global_name : String, type : TypeRef) : ValueId
      emit(GlobalLoad.new(@function.next_value_id, type, global_name))
    end

    def global_store(global_name : String, value : ValueId, type : TypeRef) : ValueId
      emit(GlobalStore.new(@function.next_value_id, type, global_name, value))
    end

    def gep(base : ValueId, indices : Array(UInt32), result_type : TypeRef, base_type : TypeRef = TypeRef::POINTER) : ValueId
      emit(GetElementPtr.new(@function.next_value_id, result_type, base, indices, base_type))
    end

    # GEP with dynamic index for pointer arithmetic
    def gep_dynamic(base : ValueId, index : ValueId, element_type : TypeRef, element_byte_size : UInt64 = 0_u64) : ValueId
      emit(GetElementPtrDynamic.new(@function.next_value_id, TypeRef::POINTER, base, index, element_type, element_byte_size))
    end

    def addressof(operand : ValueId, result_type : TypeRef) : ValueId
      emit(AddressOf.new(@function.next_value_id, result_type, operand))
    end

    # Arithmetic
    def add(left : ValueId, right : ValueId, type : TypeRef) : ValueId
      emit(BinaryOp.new(@function.next_value_id, type, BinOp::Add, left, right))
    end

    def sub(left : ValueId, right : ValueId, type : TypeRef) : ValueId
      emit(BinaryOp.new(@function.next_value_id, type, BinOp::Sub, left, right))
    end

    def mul(left : ValueId, right : ValueId, type : TypeRef) : ValueId
      emit(BinaryOp.new(@function.next_value_id, type, BinOp::Mul, left, right))
    end

    def div(left : ValueId, right : ValueId, type : TypeRef) : ValueId
      emit(BinaryOp.new(@function.next_value_id, type, BinOp::Div, left, right))
    end

    def rem(left : ValueId, right : ValueId, type : TypeRef) : ValueId
      emit(BinaryOp.new(@function.next_value_id, type, BinOp::Rem, left, right))
    end

    # Comparisons
    def eq(left : ValueId, right : ValueId) : ValueId
      emit(BinaryOp.new(@function.next_value_id, TypeRef::BOOL, BinOp::Eq, left, right))
    end

    def ne(left : ValueId, right : ValueId) : ValueId
      emit(BinaryOp.new(@function.next_value_id, TypeRef::BOOL, BinOp::Ne, left, right))
    end

    def lt(left : ValueId, right : ValueId) : ValueId
      emit(BinaryOp.new(@function.next_value_id, TypeRef::BOOL, BinOp::Lt, left, right))
    end

    def le(left : ValueId, right : ValueId) : ValueId
      emit(BinaryOp.new(@function.next_value_id, TypeRef::BOOL, BinOp::Le, left, right))
    end

    def gt(left : ValueId, right : ValueId) : ValueId
      emit(BinaryOp.new(@function.next_value_id, TypeRef::BOOL, BinOp::Gt, left, right))
    end

    def ge(left : ValueId, right : ValueId) : ValueId
      emit(BinaryOp.new(@function.next_value_id, TypeRef::BOOL, BinOp::Ge, left, right))
    end

    # Bitwise
    def bit_and(left : ValueId, right : ValueId, type : TypeRef) : ValueId
      emit(BinaryOp.new(@function.next_value_id, type, BinOp::And, left, right))
    end

    def bit_or(left : ValueId, right : ValueId, type : TypeRef) : ValueId
      emit(BinaryOp.new(@function.next_value_id, type, BinOp::Or, left, right))
    end

    def bit_xor(left : ValueId, right : ValueId, type : TypeRef) : ValueId
      emit(BinaryOp.new(@function.next_value_id, type, BinOp::Xor, left, right))
    end

    def shl(left : ValueId, right : ValueId, type : TypeRef) : ValueId
      emit(BinaryOp.new(@function.next_value_id, type, BinOp::Shl, left, right))
    end

    def shr(left : ValueId, right : ValueId, type : TypeRef) : ValueId
      emit(BinaryOp.new(@function.next_value_id, type, BinOp::Shr, left, right))
    end

    # Unary
    def neg(operand : ValueId, type : TypeRef) : ValueId
      emit(UnaryOp.new(@function.next_value_id, type, UnOp::Neg, operand))
    end

    def not(operand : ValueId) : ValueId
      emit(UnaryOp.new(@function.next_value_id, TypeRef::BOOL, UnOp::Not, operand))
    end

    def bit_not(operand : ValueId, type : TypeRef) : ValueId
      emit(UnaryOp.new(@function.next_value_id, type, UnOp::BitNot, operand))
    end

    # Casts
    def cast(kind : CastKind, value : ValueId, target_type : TypeRef) : ValueId
      emit(Cast.new(@function.next_value_id, target_type, kind, value))
    end

    def bitcast(value : ValueId, target_type : TypeRef) : ValueId
      cast(CastKind::Bitcast, value, target_type)
    end

    # Control flow values
    def phi(type : TypeRef) : Phi
      phi = Phi.new(@function.next_value_id, type)
      block.add_phi(phi)
      phi
    end

    def select(condition : ValueId, then_value : ValueId, else_value : ValueId, type : TypeRef) : ValueId
      emit(Select.new(@function.next_value_id, type, condition, then_value, else_value))
    end

    # Calls
    def call(
      callee : FunctionId,
      args : Array(ValueId),
      return_type : TypeRef,
      materialization_tx_id : String? = nil,
      materialization_contract : MaterializationContractFacts? = nil,
      resolution_handoff : Adamas::Compiler::Semantic::CallResolutionHandoff? = nil,
    ) : ValueId
      emit(Call.new(@function.next_value_id, return_type, callee, args, materialization_tx_id, materialization_contract, resolution_handoff))
    end

    def call_indirect(callee_ptr : ValueId, args : Array(ValueId), return_type : TypeRef, unwrap_union_args : Bool = true) : ValueId
      emit(IndirectCall.new(@function.next_value_id, return_type, callee_ptr, args, unwrap_union_args))
    end

    def extern_call(
      extern_name : String,
      args : Array(ValueId),
      return_type : TypeRef,
      materialization_tx_id : String? = nil,
      materialization_contract : MaterializationContractFacts? = nil,
    ) : ValueId
      emit(ExternCall.new(@function.next_value_id, return_type, extern_name, args, materialization_tx_id, materialization_contract))
    end

    # Union operations
    def union_wrap(value : ValueId, variant_type_id : Int32, union_type : TypeRef) : ValueId
      emit(UnionWrap.new(@function.next_value_id, union_type, value, variant_type_id, union_type))
    end

    # Terminators
    def ret(value : ValueId? = nil)
      block.terminator = Return.new(value)
    end

    def jump(target : BlockId)
      block.terminator = Jump.new(target)
    end

    def branch(condition : ValueId, then_block : BlockId, else_block : BlockId)
      block.terminator = Branch.new(condition, then_block, else_block)
    end

    def switch(value : ValueId, cases : Array(Tuple(Int64, BlockId)), default_block : BlockId)
      block.terminator = Switch.new(value, cases, default_block)
    end

    def unreachable
      block.terminator = Unreachable.new
    end
  end
end
