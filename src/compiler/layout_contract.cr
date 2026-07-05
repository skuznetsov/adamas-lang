# LayoutContract: the SINGLE pure decision source for the struct-value ABI
# representation question — "is a value of type T stored as INLINE bytes at its
# slot, or as an 8-byte POINTER?" (docs/abi_struct_value_sdd.md §3).
#
# Today three independent oracles answer this and drift apart (the #4 repr-flip
# family lives in their disagreements, plan §2.7):
#   - HIR  ast_to_hir.cr:39412   field_storage_size_impl
#   - MIR  hir_to_mir.cr:6353    mir_field_storage_size
#   - LLVM llvm_backend.cr:2756  container_elem_storage_size_u64_impl + :2796
#                                inline_container_struct_type?
# The ABI rework collapses them onto this one function so they cannot diverge.
#
# STEP 1a (additive, SAFE — this commit): the function and the MIR::Type memo are
# introduced but NOT yet read by any oracle (the bit is computed-but-unused). It
# reproduces the CURRENT effective HIR field-slot decision — HIR is the canonical
# layout authority: it runs first (inside align_all_class_ivars) and produces the
# field offsets the later phases copy. Steps 1b (label unification) and 1c
# (container-element reader flip) wire the readers; step 2 freezes the bit.
#
# `inline_value?` returns the boolean repr at a SLOT (pointer vs inline bytes); it
# does NOT by itself answer "8 or N bytes" — that is the slot/access split in
# SDD §4. The repr label (the 3-way taxonomy) is `repr`, used by step 1b.

module Adamas
  module LayoutContract
    # Pointer-word width for the target. Single-sourced from the MIR constant so
    # the contract and the registry never disagree on the carrier-pointer size.
    POINTER_WORD_BYTES = MIR::TARGET_POINTER_BYTES_U64

    # Pointer-word ALIGN for the target — single-sourced with POINTER_WORD_BYTES so
    # the tuple slot-layout contract and the registry never disagree on the
    # carrier-pointer alignment (kills the llvm hardcoded-8 align divergence).
    POINTER_WORD_ALIGN = MIR::TARGET_POINTER_ALIGN_U32

    # Representation taxonomy (matches LayoutProbe storage column / SDD §2).
    enum Repr
      InlineBytes      # value bytes live at the slot itself (slot == value_size)
      PointerCarrier   # struct/tuple VALUE held via an 8-byte heap pointer (V2 ABI)
      PointerReference # class reference; the 8-byte pointer IS the representation
    end

    # True when a value of `kind`/`size`/`name` lives INLINE at its slot (the slot
    # holds the value bytes); false when the slot holds an 8-byte pointer
    # (PointerReference for class refs, PointerCarrier for small struct values).
    #
    # Mirrors ast_to_hir.cr `field_storage_size_impl`'s effective repr decision:
    #   - class reference / pointer / array / proc / Nil-slot -> pointer (false)
    #   - primitive / enum / symbol / bool / char -> inline (true)
    #   - union -> inline only when wider than a pointer word (explicit payload)
    #   - struct -> inline-container families always inline; lib (C ABI) struct
    #     inline; otherwise the V2 carrier size-split (small => pointer carrier,
    #     large => inline) that step 4 will unify.
    #   - tuple/namedtuple -> small forced to pointer, large inline (HIR :39440)
    def self.inline_value?(kind : MIR::TypeKind, size : UInt64,
                           name : String, is_lib : Bool) : Bool
      case kind
      when .reference?
        # Class references: the slot is an 8-byte pointer (PointerReference).
        # String is a Reference — HIR type_size falls to ref_fallback => 8.
        false
      when .pointer?, .array?, .proc?
        # Raw pointers, heap arrays, and procs are pointer-shaped slots.
        false
      when .void?
        # Void/Nil: HIR forces the slot to the pointer word (field_storage NIL=>8).
        false
      when .union?
        # Unions carry an explicit inline payload only when wider than a pointer
        # word; narrow unions are pointer-tagged (MIR/LLVM union payload rule).
        size > POINTER_WORD_BYTES
      when .struct?
        # Lib (C ABI) structs: HIR's small-struct force-to-8 block is gated on
        # !lib, so they return their value size (inline C value). They keep their
        # dedicated path (SDD §5 guard-only); their repr is inline.
        return true if is_lib
        # Inline-container families + the V2 carrier size-split: delegated to the
        # SINGLE flip point so HIR (pre-MIR, no kind) and this predicate agree.
        user_struct_inline?(size, name)
      when .tuple?
        # HIR forces small tuples/namedtuples to the pointer word (:39440);
        # large tuples keep their inline size.
        size >= POINTER_WORD_BYTES
      else
        # Primitives, enums, symbols, bools, chars, ints, floats: inline bytes.
        true
      end
    end

    # ── Tuple slot layout (docs/inline_value_tuple_abi_sdd.md P2) ──────────────
    # THE single source for a tuple's byte geometry under the current
    # pointer-carrier element ABI, shared by every producer/consumer of tuple slot
    # layout so they cannot drift:
    #   - HIR→MIR register_tuple_types  (total size + align)
    #   - HIR→MIR lower_allocate        (constructor-arg byte offsets)
    #   - LLVM   tuple index_get const  (single element offset)
    #   - LLVM   tuple index_get runtime(offsets array feeding the stride switch)
    # Collapsing them here removes the latent divergence where HIR used the
    # platform pointer word while LLVM hardcoded 8 — both now route through
    # POINTER_WORD_BYTES / POINTER_WORD_ALIGN.
    #
    # BEHAVIOR-NEUTRAL (this commit): reproduces the CURRENT per-element rule
    # verbatim — inline (primitive/enum) → own size/align; a union strictly wider
    # than a pointer word → own size; EVERYTHING ELSE (including a NESTED TUPLE) →
    # an 8-byte pointer carrier. That last clause is the known nested-tuple alias
    # (SDD P2); a later step flips it in THIS one place (nested pod-tuple → inline)
    # once the tuple-POD predicate is unified. Callers pass an explicit element
    # Array because register_tuple_types runs before Type#element_types is
    # populated (chicken-and-egg), and a nil element ref is resolved to the POINTER
    # type by the caller, which this rule maps to the same pointer-carrier slot.
    record TupleSlotLayout, size : UInt64, align : UInt32, offsets : Array(UInt32)

    def self.tuple_slot_layout(elements : Array(MIR::Type)) : TupleSlotLayout
      size = 0_u64
      align = 1_u32
      offsets = Array(UInt32).new(elements.size)
      elements.each do |elem|
        inline = elem.kind.primitive? || elem.kind.enum?
        elem_size = if inline && elem.size > 0
                      elem.size
                    elsif elem.kind.union? && elem.size > POINTER_WORD_BYTES
                      elem.size
                    else
                      POINTER_WORD_BYTES
                    end
        elem_align = (inline && elem.alignment > 0) ? elem.alignment : POINTER_WORD_ALIGN
        # Round the running offset up to this element's alignment (align_u64 for a
        # power-of-two align == this mask), record the element start, then advance.
        size = (size + elem_align - 1) & ~(elem_align.to_u64 - 1)
        offsets << size.to_u32
        size += elem_size
        align = elem_align if elem_align > align
      end
      size = (size + align - 1) & ~(align.to_u64 - 1)
      TupleSlotLayout.new(size, align, offsets)
    end

    # Recursive "every leaf is a primitive/enum" tuple predicate — the UNBOUNDED
    # tuple-POD test the container-element storage ABI already uses. Formerly
    # duplicated byte-for-byte as inline_primitive_tuple_type? in both hir_to_mir
    # and llvm_backend; both now delegate here so the two copies cannot drift. A
    # tuple whose every element is a primitive/enum (recursively, through nested
    # tuples) is stored inline as its own value bytes.
    def self.primitive_tuple?(type : MIR::Type?) : Bool
      return false unless type
      return false unless type.kind.tuple? && type.size > 0
      elements = type.element_types
      return false unless elements && !elements.empty?
      elements.all? do |element|
        ((element.kind.primitive? || element.kind.enum?) && element.size > 0) ||
          primitive_tuple?(element)
      end
    end

    # Inline-value tuple ABI size bound (docs/inline_value_tuple_abi_sdd.md, tuned
    # in P4): a value tuple larger than this stays on the existing lowering so an
    # inline memcpy never blows up for a huge aggregate.
    INLINE_TUPLE_MAX_BYTES = 16_u64

    # BOUNDED tuple-POD gate = primitive_tuple? within the inline size bound. THE
    # single predicate the inline-value-tuple flip (a later step) and the gated
    # ContainerElemRepr census consult; the one specialization of primitive_tuple?
    # that adds the byte cap. Callers reach it only under ADAMAS_INLINE_VALUE_TUPLE,
    # so it does not affect the default (gate-off) codegen.
    def self.pod_tuple?(type : MIR::Type) : Bool
      primitive_tuple?(type) && type.size <= INLINE_TUPLE_MAX_BYTES
    end

    # 3-way repr label for the LayoutProbe storage column and the step-3 verifier
    # (step 1b routes the probe label through here so a slot is named identically
    # in every phase).
    def self.repr(kind : MIR::TypeKind, size : UInt64,
                  name : String, is_lib : Bool) : Repr
      return Repr::PointerReference if kind.reference? || kind.pointer? ||
                                       kind.array? || kind.proc?
      inline_value?(kind, size, name, is_lib) ? Repr::InlineBytes : Repr::PointerCarrier
    end

    # THE step-4 flip point for the V2 struct-value carrier ABI. True = the
    # NON-LIB struct value lives INLINE at its slot (slot == value_size); false =
    # it is held via an 8-byte pointer carrier. Today: inline-container families
    # are always inline, and a plain user struct is inline only when its value is
    # STRICTLY WIDER than a pointer word (`> POINTER_WORD_BYTES`); a struct whose
    # value is exactly one pointer word, or smaller, is a pointer carrier (the V2
    # legacy ABI at ast_to_hir.cr:39420).
    #
    # The threshold is `>` (not `>=`) to match the ACTUAL behavioural readers —
    # MIR field access uses `inline_size > pointer_word_bytes` at
    # hir_to_mir.cr:2860 (lower_field_get) and :3043 (lower_field_store_to_ptr),
    # confirmed at runtime (an exactly-8-byte struct uses load/store like a
    # pointer; a 16-byte struct uses memcopy / BorrowedAddress inline access).
    # The previous `>=` was harmless only because an 8-byte pointer and an
    # 8-byte inline value occupy the same slot size; but it was a latent
    # boundary repr-flip for step-4 (HIR would lay the slot out as an inline
    # value while MIR read it as a pointer). Aligning to `>` makes this single
    # source agree with the readers so step 4 can flip the boundary in one place.
    #
    # Step 4 flips the size split to always-inline for the perf win — and because
    # the readers (HIR field_storage_size, MIR lower_field_get/store, the LLVM
    # container oracle) all route here, that flip lands in ONE place. This is a
    # SIZE-only predicate so HIR can call it pre-MIR (no kind).
    def self.user_struct_inline?(size : UInt64, name : String) : Bool
      return true if inline_container_family?(name)
      # STEP 4 (gated, default OFF): flip small (<= pointer-word) user-struct
      # FIELDS from the legacy 8-byte pointer-carrier to inline storage. Gate OFF
      # is byte-identical to the legacy V2 ABI (`size > POINTER_WORD_BYTES`). All
      # field-repr readers (HIR field_storage_size, MIR lower_field_get/store, the
      # repr memo via inline_value?) route through this one predicate, so the flip
      # lands coherently in a single place.
      return true if step4_inline_small_structs?
      size > POINTER_WORD_BYTES
    end

    # Env gate for the step-4 small-struct inline flip (ABI rework step 4).
    # OFF (default) keeps the legacy carrier ABI; ON makes every non-lib struct
    # field inline (the Collapse). Memoised — env is constant within a compile.
    @@step4_inline_small_structs : Bool? = nil

    def self.step4_inline_small_structs? : Bool
      cached = @@step4_inline_small_structs
      return cached unless cached.nil?
      v = ::Adamas::Compiler::BootstrapEnv.get?("ADAMAS_INLINE_SMALL_STRUCTS")
      result = (v == "1" || v == "true" || v == "on")
      @@step4_inline_small_structs = result
      result
    end

    # Env gate for the container-element inline value-copy ABI (ABI rework storage
    # slice). OFF (default) is byte-identical to the legacy container ABI. In the
    # PLUMBING step ON ONLY populates + logs the fixed ContainerElemRepr label on
    # each MIR Type (STDERR census, no IR change) — no lowering site reads it yet;
    # a later behavior-changing commit wires it into the element store/load as one
    # atomic slice. Independent of step4_inline_small_structs? only because v1 is
    # leaf-storage-POD (no nested struct field whose repr would depend on the
    # field-inline flip). Memoised — env is constant within a compile.
    @@inline_pod_containers : Bool? = nil

    def self.inline_pod_containers? : Bool
      cached = @@inline_pod_containers
      return cached unless cached.nil?
      v = ::Adamas::Compiler::BootstrapEnv.get?("ADAMAS_INLINE_POD_CONTAINERS")
      result = (v == "1" || v == "true" || v == "on")
      @@inline_pod_containers = result
      result
    end

    # The container-element struct families with an implemented inline ABI
    # (mirrors llvm_backend.cr inline_container_struct_type?, :2796). Step 1c
    # replaces that runtime name match with this clause via the memo bit.
    def self.inline_container_family?(name : String) : Bool
      name.starts_with?("Slice(") ||
        name.starts_with?("StaticArray(") ||
        name.starts_with?("Hash::Entry(")
    end
  end
end
