class Adamas::HIR::AstToHir
  # A callback result restriction is a source-level tree. Its leaves retain the
  # resolved restriction spelling as well as the HIR carrier; those are not
  # interchangeable for abstract restrictions such as Int.
  class SourceBlockResultPattern
    enum Kind
      Invalid
      Concrete
      Formal
      Value
      Union
      Generic
      Tuple
      NamedTuple
    end

    getter kind : Kind
    getter restriction_name : String
    getter type_ref : TypeRef?
    getter formal_name : String?
    getter base_name : String?
    getter children : Array(SourceBlockResultPattern)
    getter labels : Array(String)
    getter valid : Bool

    def initialize(
      @kind : Kind,
      @restriction_name : String,
      @type_ref : TypeRef? = nil,
      @formal_name : String? = nil,
      @base_name : String? = nil,
      @children : Array(SourceBlockResultPattern) = [] of SourceBlockResultPattern,
      @labels : Array(String) = [] of String,
      @valid : Bool = true,
    )
    end

    def has_unbound_formal? : Bool
      return true if @kind == Kind::Formal
      @children.any?(&.has_unbound_formal?)
    end
  end

  private def build_source_block_result_pattern(
    output : String,
    owner : String?,
    formals : Array(String),
    bindings : Hash(String, String),
  ) : SourceBlockResultPattern
    old_class = @current_class
    @current_class = owner
    with_namespace_override_or_clear(owner) do
      with_isolated_type_param_map(bindings) do
        source_block_result_pattern_for(
          output,
          owner,
          formals,
          bindings,
          Set(String).new,
          allow_value_literal: false,
        )
      end
    end
  ensure
    @current_class = old_class
  end

  private def source_block_result_pattern_for(
    raw_name : String,
    owner : String?,
    formals : Array(String),
    bindings : Hash(String, String),
    active_bindings : Set(String),
    allow_value_literal : Bool,
  ) : SourceBlockResultPattern
    source = strip_fully_grouped_type_name(normalize_tuple_literal_type_name(raw_name.strip))
    return invalid_source_block_result_pattern(source) if source.empty?

    if formal_index = formals.index(source)
      if bound = bindings[source]?
        # An applied receiver Box(T) may carry a rigid outer T with the same
        # spelling. Only an absent binding denotes a free source variable.
        return invalid_source_block_result_pattern(source) if bound == source
        if bound != source
          return invalid_source_block_result_pattern(source) if active_bindings.includes?(source)
          next_active = active_bindings.dup
          next_active << source
          return source_block_result_pattern_for(
            bound,
            owner,
            formals,
            bindings,
            next_active,
            allow_value_literal: allow_value_literal,
          )
        end
      end
      return SourceBlockResultPattern.new(
        SourceBlockResultPattern::Kind::Formal,
        source,
        formal_name: formals[formal_index],
      )
    end

    # The arrow applies to the output type, so parse it before nullable syntax.
    # This preserves `A -> B?` as a Proc whose result is nullable B.
    if proc_args = proc_type_argument_names(source)
      children = proc_args.map do |arg|
        source_block_result_pattern_for(arg, owner, formals, bindings, active_bindings, allow_value_literal: false)
      end
      return source_block_result_composite(
        SourceBlockResultPattern::Kind::Generic,
        "Proc",
        children,
        owner,
        source_labels: [] of String,
      )
    end

    if source.ends_with?('?') && source.bytesize > 1
      inner = source.byte_slice(0, source.bytesize - 1).strip
      child = source_block_result_pattern_for(inner, owner, formals, bindings, active_bindings, allow_value_literal: false)
      nil_pattern = source_block_result_pattern_for("Nil", owner, formals, bindings, active_bindings, allow_value_literal: false)
      return source_block_result_union([child, nil_pattern], owner)
    end

    if has_top_level_union_separator?(source)
      children = split_union_type_name(source).map do |part|
        source_block_result_pattern_for(part, owner, formals, bindings, active_bindings, allow_value_literal: false)
      end
      flattened = [] of SourceBlockResultPattern
      children.each { |child| append_source_block_result_union_child(flattened, child) }
      return source_block_result_union(flattened, owner)
    end

    # `T*` is the source spelling of `Pointer(T)`. The Crystal parser lowers
    # that base through a global path, so keep it rooted during lexical lookup.
    # Normalize it into the same pattern shape used by an explicit Pointer(T)
    # annotation so contract matching and type-ref resolution share one identity.
    if source.ends_with?('*') && source.bytesize > 1
      inner = source.byte_slice(0, source.bytesize - 1).strip
      child = source_block_result_pattern_for(
        inner, owner, formals, bindings, active_bindings, allow_value_literal: false,
      )
      pointer_base = source_block_result_canonical_base("::Pointer", owner) ||
                     return invalid_source_block_result_pattern(source)
      return source_block_result_composite(
        SourceBlockResultPattern::Kind::Generic,
        pointer_base,
        [child],
        owner,
        source_labels: [] of String,
      )
    end

    if allow_value_literal && value_literal_name?(source)
      return SourceBlockResultPattern.new(SourceBlockResultPattern::Kind::Value, source)
    end

    if generic = split_generic_base_and_args(source)
      base_name = source_block_result_canonical_base(generic.base, owner)
      return invalid_source_block_result_pattern(source) unless base_name

      raw_args = split_generic_type_args(generic.args)
      if raw_args.empty? && !{"Tuple", "::Tuple", "NamedTuple", "::NamedTuple"}.includes?(base_name)
        return invalid_source_block_result_pattern(source)
      end
      labels = [] of String
      children = [] of SourceBlockResultPattern
      named_tuple = base_name == "NamedTuple" || base_name == "::NamedTuple"
      raw_args.each do |raw_arg|
        if named_tuple
          entry = split_named_tuple_entry(raw_arg) || return invalid_source_block_result_pattern(source)
          labels << entry[0]
          children << source_block_result_pattern_for(
            entry[1], owner, formals, bindings, active_bindings, allow_value_literal: false,
          )
        else
          children << source_block_result_pattern_for(
            raw_arg, owner, formals, bindings, active_bindings, allow_value_literal: true,
          )
        end
      end

      kind = if named_tuple
               SourceBlockResultPattern::Kind::NamedTuple
             elsif base_name == "Tuple" || base_name == "::Tuple"
               SourceBlockResultPattern::Kind::Tuple
             else
               SourceBlockResultPattern::Kind::Generic
             end
      return source_block_result_composite(kind, base_name, children, owner, source_labels: labels)
    end

    # A formal can be bound to an alias whose target is a structural type.
    # Parse that target with the same rules as an explicit source restriction;
    # treating NamedTuple(...), for example, as a nominal leaf loses its fields
    # and rejects an otherwise resolved applied owner's callback result.
    expanded = normalize_declared_type_name(source, owner, specialize_bare_generics: false)
    expanded = resolve_type_alias_chain(expanded, preserve_abstract_int: true)
    if materializable_unknown_named_type?(expanded) && !proc_literal_source_type_identity?(expanded)
      if separator = expanded.rindex("::")
        namespace = expanded.byte_slice(0, separator)
        leaf = expanded.byte_slice(separator + 2, expanded.bytesize - separator - 2)
        # A fully qualified receiver path still inherits nested types. Resolve
        # only through that owner's parents; unrelated suffixes cannot supply
        # a missing leaf, and an own type above has already won lookup.
        if inherited = nested_type_full_name_in_parents(namespace, leaf, 0)
          expanded = resolve_type_alias_chain_no_context(inherited, preserve_abstract_int: true)
        end
      end
    end
    expanded = strip_fully_grouped_type_name(normalize_tuple_literal_type_name(expanded.strip))
    if expanded != source && source_block_result_structural_source?(expanded)
      alias_key = "alias:#{source}"
      return invalid_source_block_result_pattern(source) if active_bindings.includes?(alias_key)
      next_active = active_bindings.dup
      next_active << alias_key
      return source_block_result_pattern_for(
        expanded, owner, formals, bindings, next_active, allow_value_literal: allow_value_literal,
      )
    end

    return invalid_source_block_result_pattern(source) unless source_block_result_concrete_source_exists?(source, owner)

    contract = annotation_type_contract_fragment(source, owner)
    restriction = contract.restriction_name.strip
    # `normalize_declared_type_name` canonicalizes most rooted names but may
    # drop their leading `::`. Keep that source lookup mode: it must not be
    # re-resolved relative to the block owner's namespace during matching.
    if source.starts_with?("::") && !restriction.starts_with?("::")
      restriction = "::#{restriction}"
    end
    explicit_void = restriction.lchop("::") == "Void"
    ref = contract.type_ref
    unless explicit_void || ref != TypeRef::VOID
      return invalid_source_block_result_pattern(source)
    end
    SourceBlockResultPattern.new(
      SourceBlockResultPattern::Kind::Concrete,
      restriction,
      ref,
    )
  rescue
    invalid_source_block_result_pattern(raw_name)
  end

  private def source_block_result_structural_source?(source : String) : Bool
    !proc_type_argument_names(source).nil? ||
      source.ends_with?('?') || source.ends_with?('*') ||
      source.ends_with?(".class") ||
      has_top_level_union_separator?(source) ||
      !split_generic_base_and_args(source).nil?
  end

  private def source_block_result_composite(
    kind : SourceBlockResultPattern::Kind,
    base_name : String,
    children : Array(SourceBlockResultPattern),
    owner : String?,
    source_labels : Array(String),
  ) : SourceBlockResultPattern
    return invalid_source_block_result_pattern(base_name) unless children.all?(&.valid)
    if kind == SourceBlockResultPattern::Kind::NamedTuple && source_labels.size != children.size
      return invalid_source_block_result_pattern(base_name)
    end

    restriction = case kind
                  when SourceBlockResultPattern::Kind::Tuple
                    "Tuple(#{children.map(&.restriction_name).join(", ")})"
                  when SourceBlockResultPattern::Kind::NamedTuple
                    entries = children.each_with_index.map do |child, index|
                      "#{source_labels[index]}: #{child.restriction_name}"
                    end
                    "NamedTuple(#{entries.join(", ")})"
                  else
                    "#{base_name}(#{children.map(&.restriction_name).join(", ")})"
                  end

    type_ref = nil.as(TypeRef?)
    unless children.any?(&.has_unbound_formal?)
      candidate = canonical_bound_type_ref(restriction)
      type_ref = candidate unless candidate == TypeRef::VOID && restriction.lchop("::") != "Void"
    end
    SourceBlockResultPattern.new(
      kind,
      restriction,
      type_ref,
      base_name: base_name,
      children: children,
      labels: source_labels,
    )
  end

  private def source_block_result_union(
    children : Array(SourceBlockResultPattern),
    owner : String?,
  ) : SourceBlockResultPattern
    return invalid_source_block_result_pattern("<empty union>") if children.empty?
    return children.first if children.size == 1
    return invalid_source_block_result_pattern(children.map(&.restriction_name).join(" | ")) unless children.all?(&.valid)

    restriction = normalize_union_type_name(children.map(&.restriction_name).join(" | "))
    type_ref = nil.as(TypeRef?)
    unless children.any?(&.has_unbound_formal?)
      candidate = canonical_bound_type_ref(restriction)
      type_ref = candidate unless candidate == TypeRef::VOID
    end
    SourceBlockResultPattern.new(
      SourceBlockResultPattern::Kind::Union,
      restriction,
      type_ref,
      children: children,
    )
  end

  private def append_source_block_result_union_child(
    destination : Array(SourceBlockResultPattern),
    child : SourceBlockResultPattern,
  ) : Nil
    if child.kind == SourceBlockResultPattern::Kind::Union
      child.children.each { |nested| append_source_block_result_union_child(destination, nested) }
    elsif !destination.any? { |existing| existing.restriction_name == child.restriction_name }
      destination << child
    end
  end

  private def source_block_result_canonical_base(name : String, owner : String?) : String?
    resolved = normalize_declared_type_name(name, owner, specialize_bare_generics: false)
    resolved = resolve_type_alias_chain(resolved)
    return nil if resolved.empty?
    # Generic declarations can have no bare runtime ClassInfo. The source
    # template or module index still proves that this bare structural head is
    # a declared type identity rather than an unbound source parameter.
    return nil if type_param_like?(resolved) &&
                  !@generic_templates.has_key?(resolved) &&
                  !module_defs_stripped_lookup(resolved)
    resolved
  end

  private def source_block_result_concrete_source_exists?(source : String, owner : String?) : Bool
    name = source.strip
    if name.ends_with?(".metaclass")
      name = name[0, name.bytesize - ".metaclass".bytesize]
    elsif name.ends_with?(".class")
      name = name[0, name.bytesize - ".class".bytesize]
    end

    resolved = normalize_declared_type_name(name, owner, specialize_bare_generics: false)
    resolved = resolve_type_alias_chain(resolved).strip
    return false if resolved.empty?
    proc_literal_source_type_identity?(resolved)
  rescue
    false
  end

  private def invalid_source_block_result_pattern(name : String) : SourceBlockResultPattern
    SourceBlockResultPattern.new(
      SourceBlockResultPattern::Kind::Invalid,
      name,
      valid: false,
    )
  end

  private def source_block_result_pattern_matches?(
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
    actual_literal : Bool = false,
  ) : Bool
    return false unless pattern.valid
    return false if actual == TypeRef::VOID

    bindings = {} of String => SourceCallArgument
    source_block_result_pattern_match_into?(actual, pattern, bindings, actual_literal: actual_literal)
  end

  private def source_block_result_pattern_matches_value?(
    actual : TypeRef,
    type_literal : Bool,
    pattern : SourceBlockResultPattern,
  ) : Bool
    return false unless pattern.valid

    source_block_result_pattern_matches?(actual, pattern, type_literal)
  end

  private def source_block_result_pattern_match_into?(
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
    bindings : Hash(String, SourceCallArgument),
    require_unchanged : Bool = false,
    actual_literal : Bool = false,
    actual_facts : Array({TypeRef, Bool})? = nil,
    actual_tuple_values : Array(SourceCallArgument)? = nil,
  ) : Bool
    return false unless pattern.valid
    module_restriction_key = source_block_result_module_restriction_key(pattern)
    unless pattern.kind == SourceBlockResultPattern::Kind::Formal ||
           pattern.kind == SourceBlockResultPattern::Kind::Union
      if actual_literal && pattern.kind == SourceBlockResultPattern::Kind::Concrete &&
         {"Class", "Value", "Object"}.includes?(pattern.restriction_name.lchop("::"))
        # Crystal's built-in Class is a Value. Metaclasses, including module
        # values, use that hierarchy rather than the instance carrier's parents.
        return true
      end
      unless module_restriction_key
        return false unless source_block_result_type_literal_pattern?(pattern) == actual_literal
      end
    end
    # A Void callback result is filtered at the outer boundary by
    # `source_block_result_pattern_matches?`, but Void is still a meaningful
    # component of a structural type such as `Proc(Int32, Void)`.
    if actual == TypeRef::VOID
      return false unless pattern.kind == SourceBlockResultPattern::Kind::Formal ||
                          (pattern.kind == SourceBlockResultPattern::Kind::Concrete &&
                           pattern.restriction_name.lchop("::") == "Void")
    end

    if pattern.kind == SourceBlockResultPattern::Kind::Formal
      formal = pattern.formal_name || return false
      value = SourceCallArgument.new(actual, actual_literal, value_facts: actual_facts,
        tuple_values: actual_tuple_values)
      if previous = bindings[formal]?
        return previous == value
      end
      bindings[formal] = value
      return true
    end

    if pattern.kind == SourceBlockResultPattern::Kind::Union
      return source_block_result_match_union?(actual, pattern, bindings, require_unchanged, actual_literal, actual_facts)
    end

    if actual_facts || source_block_result_union_ref?(actual)
      members = actual_facts || source_block_result_union_members(actual).try(&.map { |member| {member, actual_literal} }) || return false
      candidate = bindings.dup
      members.each do |(member, member_literal)|
        return false unless source_block_result_pattern_match_into?(member, pattern, candidate, require_unchanged, actual_literal: member_literal)
      end
      replace_source_block_result_bindings!(bindings, candidate)
      return true
    end

    if module_restriction_key
      return source_block_result_module_restriction_match_into?(
        actual, pattern, module_restriction_key, bindings, actual_literal,
      )
    end

    case pattern.kind
    when SourceBlockResultPattern::Kind::Concrete
      source_block_result_concrete_match?(actual, pattern)
    when SourceBlockResultPattern::Kind::Value
      false
    when SourceBlockResultPattern::Kind::Generic
      source_block_result_generic_match?(actual, pattern, bindings, require_unchanged)
    when SourceBlockResultPattern::Kind::Tuple
      source_block_result_tuple_match?(actual, pattern, bindings, actual_tuple_values)
    when SourceBlockResultPattern::Kind::NamedTuple
      source_block_result_named_tuple_match?(actual, pattern, bindings)
    else
      false
    end
  end

  # A plain module annotation denotes its instance methods. A value whose
  # source kind is a class literal can satisfy it only through `extend`; an
  # instance can satisfy it only through `include`. The legacy hierarchy
  # flattens both edges, so this query uses the source-owned, kind-tagged graph.
  private def source_block_result_module_restriction_key(
    pattern : SourceBlockResultPattern,
  ) : String?
    source_name = case pattern.kind
                  when SourceBlockResultPattern::Kind::Concrete
                    restriction = pattern.restriction_name
                    return nil if restriction.ends_with?(".class") || restriction.ends_with?(".metaclass")
                    restriction
                  when SourceBlockResultPattern::Kind::Generic
                    pattern.base_name || return nil
                  else
                    return nil
                  end
    identity = source_block_result_identity_name(source_block_result_carrier_name(source_name)) || return nil
    macro_module_definition_key(identity)
  end

  private def source_block_result_module_restriction_match_into?(
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
    expected_module_key : String,
    bindings : Hash(String, SourceCallArgument),
    actual_literal : Bool,
  ) : Bool
    actual_name = source_block_result_carrier_name(generic_param_type_name_from_ref(actual))
    actual_identity = source_block_result_identity_name(actual_name) || return false
    module_value = actual_literal && !macro_module_definition_key(actual_identity).nil?
    membership_kind = actual_literal ? SourceModuleMembershipKind::Extend : SourceModuleMembershipKind::Include

    owners = [] of String
    owners << actual_identity
    unless module_value
      get_parent_chain(actual_identity).each do |parent|
        owners << parent unless owners.includes?(parent)
      end
    end

    applications = [] of String
    # An instance already bounded by a module satisfies that same restriction.
    # Module class values still require an explicit extend edge, while generic
    # arguments are checked by the existing module-application matcher below.
    if !actual_literal && macro_module_definition_key(actual_identity)
      applications << actual_identity
    end
    owners.each do |owner|
      direct = source_direct_module_memberships(owner, membership_kind) || next
      direct.each do |application|
        source_block_result_module_include_projections(application).each do |projection|
          applications << projection unless applications.includes?(projection)
        end
      end
    end

    matching_bindings = [] of Hash(String, SourceCallArgument)
    applications.each do |application|
      candidate = bindings.dup
      next unless source_block_result_module_application_match_into?(
        application, expected_module_key, pattern, candidate,
      )
      matching_bindings << candidate unless matching_bindings.includes?(candidate)
    end

    return false unless matching_bindings.size == 1
    replace_source_block_result_bindings!(bindings, matching_bindings.first)
    true
  end

  # Follow only source include edges from a module application. In particular,
  # do not use the flattened class_include_instantiations table here: it also
  # records `extend` for older method lookup paths.
  private def source_block_result_module_include_projections(application : String) : Array(String)
    result = [] of String
    pending = [application]
    visited = Set(String).new
    while current = pending.shift?
      normalized = resolve_module_alias_for_include(current)
      next if normalized.empty? || visited.includes?(normalized)
      visited << normalized
      result << normalized

      direct = source_direct_class_includes(normalized)
      includes = direct || macro_transitive_module_includes(normalized)
      includes.each do |nested|
        pending << nested unless visited.includes?(nested)
      end
    end
    result
  end

  private def source_block_result_module_application_match_into?(
    application : String,
    expected_module_key : String,
    pattern : SourceBlockResultPattern,
    bindings : Hash(String, SourceCallArgument),
  ) : Bool
    actual_module_key = macro_module_definition_key(application) || return false
    actual_base = split_generic_base_and_args(actual_module_key).try(&.base) || actual_module_key
    expected_base = split_generic_base_and_args(expected_module_key).try(&.base) || expected_module_key
    actual_base = source_block_result_identity_name(actual_base) || return false
    expected_base = source_block_result_identity_name(expected_base) || return false
    return false unless actual_base == expected_base

    if pattern.kind == SourceBlockResultPattern::Kind::Generic
      actual_application = split_generic_base_and_args(application) || return false
      actual_args = split_generic_type_args(actual_application.args)
      return false unless actual_args.size == pattern.children.size
      candidate = bindings.dup
      actual_args.each_with_index do |arg, index|
        arg = arg.strip
        arg_ref = canonical_bound_type_ref(arg)
        return false unless source_block_result_generic_argument_match?(
          arg, arg_ref, pattern.children.unsafe_fetch(index), candidate,
        )
      end
      replace_source_block_result_bindings!(bindings, candidate)
      true
    else
      # A bare generic module name admits every application of it, as
      # `Array` admits `Array(Int32)`: `other : Indexable` accepts an
      # includer of `Indexable(T)`. The bases already matched above.
      true
    end
  end

  private def source_block_result_match_union?(
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
    bindings : Hash(String, SourceCallArgument),
    require_unchanged : Bool = false,
    actual_literal : Bool = false,
    actual_facts : Array({TypeRef, Bool})? = nil,
  ) : Bool
    alternatives = [] of SourceBlockResultPattern
    pattern.children.each { |child| append_source_block_result_union_child(alternatives, child) }
    formal_alternatives = alternatives.select { |child| child.kind == SourceBlockResultPattern::Kind::Formal }
    return false if formal_alternatives.size > 1

    # Crystal visits every compatible source arm for a singleton. A free T
    # binds even when a concrete arm also matches, in either source order.
    # Only a genuine actual union uses concrete-first subtraction.
    unless actual_facts || source_block_result_union_ref?(actual)
      candidate = bindings.dup
      matched = false
      alternatives.each do |alternative|
        arm_bindings = candidate.dup
        if source_block_result_pattern_match_into?(actual, alternative, arm_bindings, require_unchanged, actual_literal: actual_literal)
          replace_source_block_result_bindings!(candidate, arm_bindings)
          matched = true
        end
      end
      replace_source_block_result_bindings!(bindings, candidate) if matched
      return matched
    end

    members = actual_facts || source_block_result_union_members(actual).try(&.map { |member| {member, actual_literal} }) || return false
    constrained_alternatives = alternatives.reject { |child| child.kind == SourceBlockResultPattern::Kind::Formal }
    residual = [] of {TypeRef, Bool}

    # For a union actual, a free variable binds the remaining members as a
    # whole. Matching every member concretely leaves the variable unbound and
    # is a substitution failure, rather than an inferred NoReturn binding.
    members.each do |(member, member_literal)|
      outcomes = [] of Hash(String, SourceCallArgument)
      constrained_alternatives.each do |alternative|
        candidate = bindings.dup
        if source_block_result_pattern_match_into?(member, alternative, candidate, require_unchanged, actual_literal: member_literal)
          outcomes << candidate unless outcomes.includes?(candidate)
        end
      end
      if outcomes.size == 1
        replace_source_block_result_bindings!(bindings, outcomes.first)
      elsif outcomes.size > 1
        return false
      else
        residual << {member, member_literal}
      end
    end

    return formal_alternatives.empty? if residual.empty?
    formal_names = formal_alternatives.compact_map(&.formal_name).uniq
    return false unless formal_names.size == 1
    residual_type = source_block_result_union_type_ref(residual.map(&.[0])) || return false
    formal = formal_names.first
    residual_kinds = residual.map(&.[1]).uniq
    residual_value = SourceCallArgument.new(residual_type, residual_kinds == [true],
      value_facts: residual_kinds.size > 1 ? residual : nil)
    if previous = bindings[formal]?
      previous == residual_value
    else
      bindings[formal] = residual_value
      true
    end
  end

  private def source_block_result_union_ref?(type_ref : TypeRef) : Bool
    @module.get_type_descriptor(type_ref).try(&.kind) == TypeKind::Union
  end

  private def source_block_result_union_members(type_ref : TypeRef) : Array(TypeRef)?
    return nil unless ensure_union_descriptor_for_type_ref(type_ref)
    descriptor = union_descriptor_from_sidecar(type_ref) || return nil
    members = [] of TypeRef
    descriptor.variants.each do |variant|
      member = mir_to_hir_type_ref(variant.type_ref)
      return nil if member == TypeRef::VOID
      members << member unless members.includes?(member)
    end
    members.empty? ? nil : members
  end

  private def source_block_result_union_type_ref(members : Array(TypeRef)) : TypeRef?
    return nil if members.empty?
    return members.first if members.size == 1
    names = members.map { |member| generic_param_type_name_from_ref(member) }
    return nil if names.any?(&.empty?)
    type_ref = canonical_bound_type_ref(normalize_union_type_name(names.join(" | ")))
    type_ref == TypeRef::VOID ? nil : type_ref
  end

  private def replace_source_block_result_bindings!(
    target : Hash(String, SourceCallArgument),
    source : Hash(String, SourceCallArgument),
  ) : Nil
    target.clear
    source.each { |name, type_ref| target[name] = type_ref }
  end

  private def source_block_result_concrete_match?(
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
  ) : Bool
    actual_name = generic_param_type_name_from_ref(actual)
    expected_name = source_block_result_carrier_name(pattern.restriction_name)
    if primitive_match = source_primitive_restriction_match?(actual_name, expected_name.lchop("::"))
      return primitive_match
    end

    if expected = pattern.type_ref
      return true if actual == expected
      return true if statically_is_a_type?(actual, expected) == true
    end

    actual_identity = source_block_result_identity_name(actual_name)
    expected_identity = source_block_result_identity_name(expected_name)
    return false unless actual_identity && expected_identity
    return true if actual_identity == expected_identity

    if actual_generic = split_generic_base_and_args(actual_identity)
      return true if actual_generic.base == expected_identity
    end

    return true if get_parent_chain(actual_identity).includes?(expected_identity)
    source_generic_ancestor_projections(actual_identity).any? do |projection|
      source_block_result_identity_name(projection) == expected_identity
    end
  end

  private def source_block_result_carrier_name(name : String) : String
    source = name.strip
    if source.ends_with?(".metaclass")
      source[0, source.bytesize - ".metaclass".bytesize]
    elsif source.ends_with?(".class")
      source[0, source.bytesize - ".class".bytesize]
    else
      source
    end
  end

  private def source_block_result_identity_name(name : String) : String?
    return nil if name.empty? || name == "Unknown"
    resolved = resolve_type_alias_chain(name.strip)
    return nil if resolved.empty?
    resolved.lchop("::")
  end

  private def source_block_result_generic_match?(
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
    bindings : Hash(String, SourceCallArgument),
    require_unchanged : Bool = false,
  ) : Bool
    if pattern.base_name.try(&.lchop("::")) == "Proc"
      return source_block_result_proc_match?(actual, pattern, bindings, require_unchanged)
    end

    actual_name = generic_param_type_name_from_ref(actual)
    projections = source_generic_ancestor_projections(actual_name)
    source_block_result_generic_parent_projections(actual_name).each do |projection|
      projections << projection unless projections.includes?(projection)
    end
    projections.unshift(actual_name) unless projections.includes?(actual_name)
    matches = [] of Hash(String, SourceCallArgument)
    projections.each do |projection|
      info = split_generic_base_and_args(projection) || next
      projected_base = source_block_result_identity_name(info.base) || next
      next unless projected_base == pattern.base_name
      args = split_generic_type_args(info.args)
      next unless args.size == pattern.children.size

      candidate = bindings.dup
      compatible = true
      args.each_with_index do |arg, index|
        child = pattern.children.unsafe_fetch(index)
        arg_ref = canonical_bound_type_ref(arg.strip)
        unless source_block_result_generic_argument_match?(arg.strip, arg_ref, child, candidate)
          compatible = false
          break
        end
      end
      matches << candidate if compatible && !matches.includes?(candidate)
    end

    return false unless matches.size == 1
    replace_source_block_result_bindings!(bindings, matches.first)
    true
  end

  private def source_block_result_generic_parent_projections(actual_name : String) : Array(String)
    result = [] of String
    pending = [actual_name]
    visited = Set(String).new
    while current = pending.shift?
      split = split_generic_base_and_args(current) || next
      base = source_block_result_identity_name(split.base) || next
      next if visited.includes?(base)
      visited << base

      template = @generic_templates[base]?
      next unless template
      next unless template.type_params.size == (args = split_generic_type_args(split.args)).size
      parent_slice = template.node.super_name || next
      raw_parent = safe_slice_to_string(parent_slice) || next
      parameter_bindings = {} of String => String
      template.type_params.each_with_index do |formal, index|
        parameter_bindings[formal] = args.unsafe_fetch(index).strip
      end

      parent = with_arena(template.arena) do
        old_class = @current_class
        @current_class = base
        begin
          with_namespace_override_or_clear(base) do
            with_isolated_type_param_map(parameter_bindings) do
              normalize_declared_type_name(raw_parent, base, specialize_bare_generics: false)
            end
          end
        ensure
          @current_class = old_class
        end
      end
      next if parent.empty? || parent == current
      result << parent unless result.includes?(parent)
      pending << parent
    end
    result
  rescue
    [] of String
  end

  # Generic arguments use Crystal's source restriction rules here. In
  # particular, each concrete argument can match one arm of a bound union;
  # this is distinct from assigning one nominal generic instance to another.
  # Keep open formals on the structural path so they can still bind from
  # callback output.
  private def source_block_result_generic_argument_match?(
    actual_name : String,
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
    bindings : Hash(String, SourceCallArgument),
  ) : Bool
    source_value = source_call_argument_from_name(actual_name)
    case pattern.kind
    when SourceBlockResultPattern::Kind::Value
      actual_value = normalize_declared_type_name(actual_name.strip, nil, specialize_bare_generics: false)
      actual_value == pattern.restriction_name
    when SourceBlockResultPattern::Kind::Union
      return source_block_result_pattern_match_into?(actual, pattern, bindings, true,
        actual_literal: source_value.type_literal, actual_facts: source_value.value_facts) if pattern.has_unbound_formal?
      source_block_result_union_argument_restriction_match?(actual, pattern, bindings, source_value)
    when SourceBlockResultPattern::Kind::Generic
      if pattern.base_name.try(&.lchop("::")) == "Proc"
        source_block_result_proc_match?(actual, pattern, bindings, true)
      elsif pattern.has_unbound_formal?
        source_block_result_pattern_match_into?(actual, pattern, bindings, true,
          actual_literal: source_value.type_literal, actual_facts: source_value.value_facts)
      else
        source_block_result_invariant_generic_match?(actual_name, pattern, bindings)
      end
    when SourceBlockResultPattern::Kind::Tuple
      source_block_result_pattern_match_into?(actual, pattern, bindings, true,
        actual_literal: source_value.type_literal, actual_facts: source_value.value_facts)
    when SourceBlockResultPattern::Kind::NamedTuple
      source_block_result_pattern_match_into?(actual, pattern, bindings,
        actual_literal: source_value.type_literal, actual_facts: source_value.value_facts)
    when SourceBlockResultPattern::Kind::Concrete
      source_block_result_invariant_concrete_argument_match?(actual_name, actual, pattern)
    else
      source_block_result_pattern_match_into?(actual, pattern, bindings,
        actual_literal: source_value.type_literal, actual_facts: source_value.value_facts)
    end
  end

  private def source_block_result_invariant_concrete_argument_match?(
    actual_name : String,
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
  ) : Bool
    expected_name = pattern.restriction_name.lchop("::")
    if primitive_match = source_primitive_restriction_match?(actual_name, expected_name)
      return primitive_match
    end
    if registered_abstract_class_name?(expected_name)
      return source_block_result_concrete_match?(actual, pattern)
    end

    actual_identity = source_block_result_invariant_leaf_name(actual_name)
    expected_identity = source_block_result_invariant_leaf_name(expected_name)
    !!actual_identity && actual_identity == expected_identity
  end

  private def source_block_result_invariant_leaf_name(name : String) : String?
    source = strip_fully_grouped_type_name(name.strip)
    return nil if source.empty? || source.includes?('(') || has_top_level_union_separator?(source)
    resolved = resolve_type_alias_chain(source, preserve_abstract_int: true).strip
    return nil if resolved.empty?
    resolved.lchop("::")
  rescue
    nil
  end

  private def source_block_result_union_argument_restriction_match?(
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
    bindings : Hash(String, SourceCallArgument),
    source_value : SourceCallArgument,
  ) : Bool
    members = if facts = source_value.value_facts
                facts
              elsif source_block_result_union_ref?(actual)
                (source_block_result_union_members(actual) || return false).map { |member| {member, source_value.type_literal} }
              else
                [{actual, source_value.type_literal}]
              end
    alternatives = [] of SourceBlockResultPattern
    pattern.children.each { |child| append_source_block_result_union_child(alternatives, child) }
    return false if alternatives.empty?

    # Crystal's union restriction matches every actual arm against any
    # compatible source arm; it does not require a one-to-one pairing. This
    # matters for `Array(Int32) | Array(String)` restricted by
    # `Array(Int32 | String)`.
    members.all? do |(member, literal)|
      alternatives.any? do |alternative|
        candidate = bindings.dup
        source_block_result_generic_argument_match?(
          proc_source_type_name(member, literal), member, alternative, candidate,
        )
      end
    end
  end

  private def source_block_result_invariant_generic_match?(
    actual_name : String,
    pattern : SourceBlockResultPattern,
    bindings : Hash(String, SourceCallArgument),
  ) : Bool
    info = split_generic_base_and_args(actual_name) || return false
    actual_base = source_block_result_canonical_base(info.base, nil) || return false
    return false unless actual_base == pattern.base_name
    args = split_generic_type_args(info.args)
    return false unless args.size == pattern.children.size

    candidate = bindings.dup
    args.each_with_index do |arg, index|
      arg_ref = canonical_bound_type_ref(arg.strip)
      return false unless source_block_result_generic_argument_match?(
        arg.strip, arg_ref, pattern.children.unsafe_fetch(index), candidate,
      )
    end
    replace_source_block_result_bindings!(bindings, candidate)
    true
  end

  # Proc restrictions have source-specific result rules: an expected Nil/Void
  # discards the callback result, and an actual NoReturn result satisfies any
  # output restriction. Input slots and all other outputs use the same
  # structural matcher as the surrounding source contract.
  private def source_block_result_proc_match?(
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
    bindings : Hash(String, SourceCallArgument),
    require_unchanged : Bool = false,
  ) : Bool
    descriptor = @module.get_type_descriptor(actual)
    return false unless descriptor && descriptor.kind == TypeKind::Proc
    params = descriptor.type_params
    return false if params.empty? || params.size != pattern.children.size

    candidate = bindings.dup
    last = params.size - 1
    index = 0
    while index < last
      return false unless source_block_result_pattern_match_into?(
        params.unsafe_fetch(index), pattern.children.unsafe_fetch(index), candidate, true,
        actual_literal: descriptor.proc_type_literal_slot?(index),
        actual_facts: descriptor.proc_source_type_facts_at(index),
      )
      index += 1
    end

    expected_result = pattern.children.unsafe_fetch(last)
    actual_result = params.unsafe_fetch(last)
    if source_block_result_proc_discards_result?(expected_result)
      # A direct Proc restriction may adapt any callback result to Nil. When
      # Proc appears inside a type argument or another structural slot, the
      # surrounding restriction requires the original value to be preserved.
      return false if require_unchanged &&
                      (get_type_name_from_ref(actual_result) != "Nil" || descriptor.proc_type_literal_slot?(last) ||
                      !descriptor.proc_source_type_facts_at(last).nil?)
      replace_source_block_result_bindings!(bindings, candidate)
      return true
    end
    if get_type_name_from_ref(actual_result) == "NoReturn" && !descriptor.proc_type_literal_slot?(last)
      replace_source_block_result_bindings!(bindings, candidate)
      return true
    end
    return false unless source_block_result_pattern_match_into?(
      actual_result, expected_result, candidate, true,
      actual_literal: descriptor.proc_type_literal_slot?(last),
      actual_facts: descriptor.proc_source_type_facts_at(last),
    )
    replace_source_block_result_bindings!(bindings, candidate)
    true
  end

  private def source_block_result_proc_discards_result?(pattern : SourceBlockResultPattern) : Bool
    return false unless pattern.kind == SourceBlockResultPattern::Kind::Concrete
    !pattern.restriction_name.ends_with?(".class") &&
      !pattern.restriction_name.ends_with?(".metaclass") &&
      {"Nil", "Void"}.includes?(pattern.restriction_name.lchop("::"))
  end

  private def source_block_result_type_literal_pattern?(pattern : SourceBlockResultPattern) : Bool
    proc_annotation_type_literal?(pattern.restriction_name)
  end

  private def source_block_result_tuple_match?(
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
    bindings : Hash(String, SourceCallArgument),
    actual_tuple_values : Array(SourceCallArgument)? = nil,
  ) : Bool
    descriptor = @module.get_type_descriptor(actual)
    return false unless descriptor && descriptor.kind == TypeKind::Tuple
    return false unless descriptor.type_params.size == pattern.children.size

    candidate = bindings.dup
    if values = actual_tuple_values
      return false unless values.size == descriptor.type_params.size
      values.each_with_index do |source_value, index|
        # The structured witness and the actual HIR descriptor must describe
        # the same tuple slot. This prevents a stale source witness from being
        # paired with another specialization's ABI tuple.
        return false unless descriptor.type_params.unsafe_fetch(index) == source_value.type_ref
        return false unless source_block_result_pattern_match_into?(
          source_value.type_ref,
          pattern.children.unsafe_fetch(index),
          candidate,
          true,
          actual_literal: source_value.type_literal,
          actual_facts: source_value.value_facts,
          actual_tuple_values: source_value.tuple_values,
        )
      end
      replace_source_block_result_bindings!(bindings, candidate)
      return true
    end

    info = split_generic_base_and_args(descriptor.name) || return false
    source_names = split_generic_type_args(info.args)
    return false unless source_names.size == descriptor.type_params.size
    descriptor.type_params.each_with_index do |element, index|
      source_value = source_call_argument_from_name(source_names[index])
      return false unless source_block_result_pattern_match_into?(element, pattern.children.unsafe_fetch(index), candidate, true,
        actual_literal: source_value.type_literal, actual_facts: source_value.value_facts)
    end
    replace_source_block_result_bindings!(bindings, candidate)
    true
  end

  private def source_block_result_named_tuple_match?(
    actual : TypeRef,
    pattern : SourceBlockResultPattern,
    bindings : Hash(String, SourceCallArgument),
  ) : Bool
    descriptor = @module.get_type_descriptor(actual)
    return false unless descriptor && descriptor.kind == TypeKind::NamedTuple
    entries = concrete_named_tuple_entries(actual) || return false
    actual_labels = entries.map { |entry| entry[0] }.sort
    expected_labels = pattern.labels.sort
    return false unless actual_labels == expected_labels
    info = split_generic_base_and_args(descriptor.name) || return false
    source_names = split_generic_type_args(info.args).map { |name| split_named_tuple_entry(name).try(&.[1]) }

    candidate = bindings.dup
    pattern.labels.each_with_index do |label, index|
      entry = entries.find { |item| item[0] == label } || return false
      # Crystal's NamedTuple restriction requires each field restriction to
      # succeed, but unlike TupleInstanceType it does not require the restricted
      # field type to equal the original field type. Keep Proc's Nil adaptation
      # available in this position.
      source_name = source_names[entry[1]]? || return false
      source_value = source_call_argument_from_name(source_name)
      unless source_block_result_pattern_match_into?(entry[2], pattern.children.unsafe_fetch(index), candidate,
               actual_literal: source_value.type_literal, actual_facts: source_value.value_facts)
        return false
      end
    end
    replace_source_block_result_bindings!(bindings, candidate)
    true
  end
end
