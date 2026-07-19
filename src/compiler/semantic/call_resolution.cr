# Semantic call-resolution carrier and compile-session identity encoder.
#
# This file intentionally stops at the semantic boundary. It does not know
# about HIR/MIR, mangled names, ABI coercions, or materialization caches.

require "../frontend/ast"
require "./identity/def_identity"
require "./identity/name_id"
require "./identity/callsite_identity"
require "./identity/call_resolution_handoff"
require "./identity/resolution_id"
require "./identity/semantic_type_id"
require "./identity/type_declaration_identity"
require "./types/type"
require "./types/primitive_type"
require "./types/class_type"
require "./types/instance_type"
require "./types/union_type"
require "./types/array_type"
require "./types/range_type"
require "./types/hash_type"
require "./types/tuple_type"
require "./types/named_tuple_type"
require "./types/proc_type"
require "./types/pointer_type"
require "./types/module_type"
require "./types/enum_type"
require "./types/type_parameter"

module Adamas::Compiler::Semantic
  # The encoder is deliberately compile-session scoped. Type objects are
  # accepted at this boundary, then immediately reduced to owner-scoped IDs;
  # no Type or source String is retained by CallResolution.
  class SemanticTypeEncoder
    getter table : SemanticTypeInternTable

    def initialize(
      @table : SemanticTypeInternTable = SemanticTypeInternTable.new,
      @arena : Frontend::AstArena? = nil,
    )
    end

    def encode(type : Type) : SemanticTypeId
      encode_uncached(type)
    end

    private def encode_uncached(type : Type) : SemanticTypeId
      case type
      when PrimitiveType
        @table.primitive(type.name)
      when ClassType
        kind = type.symbol.is_struct? ? TypeKind::Struct : TypeKind::Class
        encode_nominal(type.symbol, kind, type.type_args)
      when InstanceType
        encode_nominal(type.class_symbol, TypeKind::Instance, type.type_args)
      when ModuleType
        encode_nominal(type.symbol, TypeKind::Module, type.type_args)
      when EnumType
        encode_nominal(type.symbol, TypeKind::Enum, nil)
      when UnionType
        @table.union(type.types.map { |member| encode(member) })
      when ArrayType
        @table.generic("Array", TypeKind::Array, [encode(type.element_type)])
      when HashType
        @table.generic("Hash", TypeKind::Hash, [encode(type.key_type), encode(type.value_type)])
      when RangeType
        @table.generic("Range", TypeKind::Generic, [encode(type.begin_type), encode(type.end_type)])
      when TupleType
        @table.tuple(type.element_types.map { |member| encode(member) })
      when NamedTupleType
        # NamedTuple field identity is not yet represented by an ordered
        # NameId/value key. Do not reintroduce string identity here.
        raise UnsupportedSemanticTypeError.new(type.class.name)
      when ProcType
        @table.proc_type(type.param_types.map { |param| encode(param) }, encode(type.return_type))
      when PointerType
        @table.pointer(encode(type.element_type))
      when TypeParameter
        # TypeParameter has name-only structural equality in the legacy model
        # and should never survive as a final inferred type. Without a typed
        # declaration owner, admitting it would collapse unrelated `T`s.
        raise UnsupportedSemanticTypeError.new(type.class.name)
      else
        raise UnsupportedSemanticTypeError.new(type.class.name)
      end
    end

    private def encode_nominal(symbol : Symbol, kind : TypeKind, type_args : Array(Type)?) : SemanticTypeId
      arena = @arena || raise UnsupportedSemanticTypeError.new(symbol.class.name)
      arena_id = arena.object_id.to_u64
      raise UnsupportedSemanticTypeError.new(symbol.class.name) unless symbol.direct_declaration_origin?

      node_id = symbol.node_id
      raise UnsupportedSemanticTypeError.new(symbol.class.name) if node_id.invalid? || node_id.index >= arena.size

      node = arena[node_id]
      source_backed = case symbol
                      when ClassSymbol
                        node.is_a?(Frontend::ClassNode)
                      when ModuleSymbol
                        node.is_a?(Frontend::ModuleNode)
                      when EnumSymbol
                        node.is_a?(Frontend::EnumNode)
                      else
                        false
                      end
      raise UnsupportedSemanticTypeError.new(symbol.class.name) unless source_backed

      encoded_args = type_args ? type_args.map { |arg| encode(arg) } : [] of SemanticTypeId
      @table.nominal(
        symbol.name,
        kind,
        TypeDeclarationIdentity.new(arena_id, node_id.index),
        encoded_args,
      )
    end
  end

  class UnsupportedSemanticTypeError < Exception
    getter type_name : String

    def initialize(@type_name : String)
      super("semantic identity encoding is unsupported for #{type_name}")
    end
  end

  # Ordered, owner-scoped named arguments. Unlike DefInstanceKey, this is not
  # a cache key and therefore never sorts the source axis.
  alias OrderedNamedSemanticArguments = ImmutableValueArray({NameId, SemanticTypeId})

  struct CallResolution
    getter resolution_id : ResolutionId
    getter callsite : CallsiteIdentity
    getter def_identity : DefIdentity
    getter receiver_type : SemanticTypeId?
    getter arg_types : SemanticTypeComponents
    getter block_type : SemanticTypeId?
    getter named_arg_types : OrderedNamedSemanticArguments?

    def initialize(
      @resolution_id : ResolutionId,
      resolution_scope : ResolutionScope,
      semantic_type_context : SemanticTypeInternTable,
      @callsite : CallsiteIdentity,
      @def_identity : DefIdentity,
      @receiver_type : SemanticTypeId?,
      @arg_types : SemanticTypeComponents,
      @block_type : SemanticTypeId?,
      @named_arg_types : OrderedNamedSemanticArguments? = nil,
    )
      begin
        validate_identity_scopes!(resolution_scope, semantic_type_context)
      rescue ex
        @resolution_id.cancel_pending_issue!
        raise ex
      end
    end

    private def validate_identity_scopes!(
      resolution_scope : ResolutionScope,
      semantic_type_context : SemanticTypeInternTable,
    ) : Nil
      unless @resolution_id.owned_by?(resolution_scope)
        raise ArgumentError.new("foreign, raw, or UNKNOWN ResolutionId cannot enter CallResolution")
      end
      unless resolution_scope.owns_semantic_context?(semantic_type_context)
        raise ArgumentError.new("ResolutionScope and semantic type context do not share an owner")
      end
      unless @callsite.arena_id == resolution_scope.arena_id &&
             @def_identity.arena_id == resolution_scope.arena_id
        raise ArgumentError.new("CallResolution arena owners do not match its ResolutionScope")
      end

      semantic_scope : SemanticTypeId? = nil
      if receiver = @receiver_type
        semantic_scope = validate_semantic_type!(receiver, semantic_scope, semantic_type_context)
      end
      @arg_types.each do |type|
        semantic_scope = validate_semantic_type!(type, semantic_scope, semantic_type_context)
      end
      if block = @block_type
        semantic_scope = validate_semantic_type!(block, semantic_scope, semantic_type_context)
      end

      if named = @named_arg_types
        named.each do |name, type|
          unless name.canonical?
            raise ArgumentError.new("raw or UNKNOWN NameId cannot enter CallResolution")
          end
          unless type.accepts_name?(name)
            raise ArgumentError.new("NameId is not owned by the SemanticTypeInternTable for CallResolution")
          end
          semantic_scope = validate_semantic_type!(type, semantic_scope, semantic_type_context)
        end
      end

      resolution_scope.claim!(@resolution_id)
    end

    private def validate_semantic_type!(
      type : SemanticTypeId,
      scope : SemanticTypeId?,
      semantic_type_context : SemanticTypeInternTable,
    ) : SemanticTypeId
      unless type.owned_by?(semantic_type_context)
        raise ArgumentError.new("SemanticTypeId is not owned by the CallResolution semantic context")
      end
      if previous = scope
        raise ArgumentError.new("mixed SemanticTypeId scopes cannot enter CallResolution") unless previous.same_owner?(type)
        previous
      else
        type
      end
    end
  end

  # Producer-side construction seam for the lightweight carrier. It accepts a
  # claimed CallResolution, then revalidates its source nodes through the
  # retained ResolutionScope owner. Raw, foreign, or coordinate-only facts
  # cannot mint a HIR/MIR handoff; converting the same admitted resolution
  # again reconstructs an equal carrier with the same ResolutionId.
  class CallResolutionHandoff
    def self.from(resolution : CallResolution) : self?
      return nil if resolution.named_arg_types
      unless resolution.resolution_id.canonical?
        raise ArgumentError.new("CallResolution handoff requires a canonical ResolutionId")
      end
      unless resolution.resolution_id.owns_source_coordinates?(resolution.callsite, resolution.def_identity)
        raise ArgumentError.new("CallResolution handoff requires source-backed call and definition coordinates")
      end

      new(
        resolution.resolution_id,
        resolution.callsite,
        DefInstanceKey.new(
          def_identity: resolution.def_identity,
          receiver_type: resolution.receiver_type,
          arg_types: resolution.arg_types,
          block_type: resolution.block_type,
        ),
      )
    end
  end

  # Small compile-session owner for semantic identity production. The owner
  # retains the latest resolution per typed callsite and one diagnostic spelling
  # per interned name. It borrows the enclosing AstArena for declaration checks
  # and retains no Type objects or individual call AST nodes.
  class CallResolutionContext
    getter semantic_type_context : SemanticTypeInternTable
    getter resolution_scope : ResolutionScope

    def initialize(
      @arena : Frontend::AstArena,
      @semantic_type_context : SemanticTypeInternTable = SemanticTypeInternTable.new,
    )
      @arena_id = @arena.object_id.to_u64
      @encoder = SemanticTypeEncoder.new(@semantic_type_context, @arena)
      @resolution_scope = ResolutionScope.new(@arena, @semantic_type_context)
      @resolutions = {} of CallsiteIdentity => CallResolution
    end

    def encode(type : Type) : SemanticTypeId
      @encoder.encode(type)
    end

    def record(
      callsite_expr_id : Frontend::ExprId,
      callsite : CallsiteIdentity,
      def_identity : DefIdentity,
      receiver_type : Type,
      arg_types : Array(Type),
      block_type : Type? = nil,
      named_arg_types : Array({String, Type})? = nil,
    ) : CallResolution?
      return nil unless callsite.arena_id == @arena_id
      return nil unless callsite.expr_index == callsite_expr_id.index
      return nil unless def_identity.arena_id == @arena_id
      return nil if def_identity.expr_index < 0 || def_identity.expr_index >= @arena.size
      return nil if callsite_expr_id.invalid? || callsite_expr_id.index >= @arena.size
      return nil unless @arena[callsite_expr_id].is_a?(Frontend::CallNode)
      return nil unless @arena[Frontend::ExprId.new(def_identity.expr_index)].is_a?(Frontend::DefNode)

      encoded_receiver = encode(receiver_type)
      encoded_args = SemanticTypeComponents.map_owned(arg_types) { |type| encode(type) }
      encoded_block = block_type.try { |type| encode(type) }
      encoded_named = named_arg_types.try do |entries|
        OrderedNamedSemanticArguments.map_owned(entries) do |name, type|
          {@semantic_type_context.names.intern(name), encode(type)}
        end
      end

      resolution = CallResolution.new(
        @resolution_scope.issue,
        @resolution_scope,
        @semantic_type_context,
        callsite,
        def_identity,
        encoded_receiver,
        encoded_args,
        encoded_block,
        encoded_named,
      )
      @resolutions[callsite] = resolution
      resolution
    rescue ex : UnsupportedSemanticTypeError
      # Unsupported shapes fail closed: no partial record is published and
      # semantic typing continues through the existing path.
      nil
    end

    def [](callsite : CallsiteIdentity) : CallResolution?
      return nil unless callsite.arena_id == @arena_id
      @resolutions[callsite]?
    end
  end
end
