# Canonical semantic keys for generic templates and instances.
#
# These keys intentionally keep the display/rendered name out of equality.
# Rendered names are diagnostics and LLVM/HIR symbol inputs; they are not stable
# enough to decide whether two generic templates or instances are the same
# semantic entity.

require "./def_identity"
require "./semantic_type_id"

module Adamas::Compiler::Semantic
  struct GenericTemplateKey
    getter owner_name : String
    getter template_leaf_name : String
    getter source_def_identity : DefIdentity
    getter declared_type_param_names : Array(String)

    def initialize(
      @owner_name : String,
      @template_leaf_name : String,
      @source_def_identity : DefIdentity,
      declared_type_param_names : Array(String),
    )
      @declared_type_param_names = declared_type_param_names.dup
    end

    def ==(other : GenericTemplateKey) : Bool
      @owner_name == other.owner_name &&
        @template_leaf_name == other.template_leaf_name &&
        @source_def_identity == other.source_def_identity &&
        @declared_type_param_names == other.declared_type_param_names
    end

    def hash(hasher)
      hasher = @owner_name.hash(hasher)
      hasher = @template_leaf_name.hash(hasher)
      hasher = @source_def_identity.hash(hasher)
      hasher = @declared_type_param_names.hash(hasher)
      hasher
    end

    def display_name : String
      suffix = @declared_type_param_names.empty? ? "" : "(#{@declared_type_param_names.join(", ")})"
      if @owner_name.empty?
        "#{@template_leaf_name}#{suffix}"
      else
        "#{@owner_name}::#{@template_leaf_name}#{suffix}"
      end
    end

    def to_s(io : IO) : Nil
      io << "GenericTemplateKey(owner=" << @owner_name
      io << " leaf=" << @template_leaf_name
      io << " source=" << @source_def_identity
      io << " params=[" << @declared_type_param_names.join(", ") << "])"
    end
  end

  struct GenericInstanceKey
    getter template_key : GenericTemplateKey
    getter receiver_type_identity : SemanticTypeId?
    getter specialization_arg_identities : Array(SemanticTypeId)
    getter lexical_context_owner : String?

    def initialize(
      @template_key : GenericTemplateKey,
      @receiver_type_identity : SemanticTypeId? = nil,
      specialization_arg_identities : Array(SemanticTypeId) = [] of SemanticTypeId,
      @lexical_context_owner : String? = nil,
    )
      @specialization_arg_identities = specialization_arg_identities.dup
    end

    def ==(other : GenericInstanceKey) : Bool
      @template_key == other.template_key &&
        @receiver_type_identity == other.receiver_type_identity &&
        @specialization_arg_identities == other.specialization_arg_identities &&
        @lexical_context_owner == other.lexical_context_owner
    end

    def hash(hasher)
      hasher = @template_key.hash(hasher)
      hasher = @receiver_type_identity.hash(hasher)
      hasher = @specialization_arg_identities.hash(hasher)
      hasher = @lexical_context_owner.hash(hasher)
      hasher
    end

    def to_s(io : IO) : Nil
      io << "GenericInstanceKey(template=" << @template_key
      if recv = @receiver_type_identity
        io << " recv=" << recv
      end
      unless @specialization_arg_identities.empty?
        io << " args=[" << @specialization_arg_identities.join(", ") << "]"
      end
      if owner = @lexical_context_owner
        io << " lexical=" << owner
      end
      io << ")"
    end
  end
end
