require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  # Model a fresh-demand call from inside a body: declarations have been
  # registered, but neither the helper's base nor exact return cache exists.
  # Keep the caller's inference environment and caches intact around the probe.
  def __test_bare_class_call_return_with_cold_cache(
    owner_name : String,
    caller_method : String,
    helper_method : String,
    helper_owner_name : String = owner_name,
    additional_helper_methods : Array(String) = [] of String,
    seed_base_return_type : String? = nil,
    seed_instance_base_return_type : String? = nil,
    caller_type_bindings : Hash(String, String) = {} of String => String,
  ) : String?
    caller_name = "#{owner_name}.#{caller_method}"
    helper_base = "#{helper_owner_name}.#{helper_method}"
    helper_bases = [helper_base]
    additional_helper_methods.each do |name|
      helper_bases << "#{helper_owner_name}.#{name}"
    end

    caller_defs = @function_defs.select do |name, _|
      name == caller_name || name.starts_with?("#{caller_name}$")
    end.values.uniq(&.object_id)
    raise "expected one registered caller #{caller_name}, got #{caller_defs.size}" unless caller_defs.size == 1
    caller_def = caller_defs.first
    caller_body = caller_def.body || raise "caller #{caller_name} has no body"
    call_expr = caller_body.last? || raise "caller #{caller_name} has an empty body"
    raise "probe caller tail must be a CallNode" unless node_for_expr(call_expr).is_a?(Adamas::Compiler::Frontend::CallNode)
    helper_bases.each do |base|
      unless @function_defs.keys.any? { |name| name == base || name.starts_with?("#{base}$") }
        raise "missing registered helper #{base}"
      end
    end

    old_function_types = @function_types
    old_base_return_types = @function_base_return_types
    old_infer_type_cache = @infer_type_cache
    old_infer_type_guarded = @infer_type_guarded
    old_infer_body_context = @infer_body_context
    old_current_class = @current_class
    old_current_method = @current_method
    old_current_def = @current_def_node
    old_infer_self_type_name = @infer_self_type_name
    old_current_method_is_class = @current_method_is_class
    old_typeof_locals = @current_typeof_locals
    old_typeof_names = @current_typeof_local_names
    old_cache_version = @infer_type_cache_version
    old_function_type_revision = @function_type_revision
    old_base_return_type_revision = @function_base_return_type_revision
    old_callsite_return_stack = @infer_callsite_return_stack
    old_callsite_return_frames = @infer_callsite_return_frames
    old_callsite_return_lows = @infer_callsite_return_lows
    old_callsite_return_anchored = @infer_callsite_return_anchored
    old_callsite_return_memo = @infer_callsite_return_memo
    old_return_unproven_reads = @return_infer_unproven_local_reads

    begin
      @function_types = old_function_types.dup
      @function_base_return_types = old_base_return_types.dup
      @function_types.keys.each do |name|
        if helper_bases.any? { |base| name == base || name.starts_with?("#{base}$") }
          @function_types.delete(name)
        end
      end
      @function_base_return_types.keys.each do |name|
        if helper_bases.any? { |base| name == base || name.starts_with?("#{base}$") }
          @function_base_return_types.delete(name)
        end
      end
      if seed_base = seed_base_return_type
        @function_base_return_types[helper_base] = type_ref_for_name(seed_base)
      end
      if seed_instance = seed_instance_base_return_type
        @function_base_return_types["#{owner_name}##{helper_method}"] = type_ref_for_name(seed_instance)
      end

      @infer_type_cache = old_infer_type_cache.dup
      @infer_type_cache.clear
      @infer_type_guarded = old_infer_type_guarded.dup
      @infer_type_guarded.clear
      @infer_callsite_return_stack = old_callsite_return_stack.dup
      @infer_callsite_return_stack.clear
      @infer_callsite_return_frames = old_callsite_return_frames.dup
      @infer_callsite_return_frames.clear
      @infer_callsite_return_lows = old_callsite_return_lows.dup
      @infer_callsite_return_lows.clear
      @infer_callsite_return_anchored = old_callsite_return_anchored.dup
      @infer_callsite_return_anchored.clear
      @infer_callsite_return_memo = old_callsite_return_memo.dup
      @infer_callsite_return_memo.clear
      @return_infer_unproven_local_reads = old_return_unproven_reads.dup
      @return_infer_unproven_local_reads.clear
      @infer_body_context = caller_body
      @current_class = owner_name
      @current_method = caller_method
      @current_def_node = caller_def
      @infer_self_type_name = owner_name
      @current_method_is_class = true
      caller_locals = {} of String => Adamas::HIR::TypeRef
      caller_local_names = {} of String => String
      caller_type_bindings.each do |name, type_name|
        type = type_ref_for_name(type_name)
        next if type == Adamas::HIR::TypeRef::VOID
        caller_locals[name] = type
        caller_local_names[name] = get_type_name_from_ref(type)
      end
      @current_typeof_locals = caller_locals
      @current_typeof_local_names = caller_local_names

      inferred = infer_type_from_expr(call_expr, owner_name)
      inferred.try { |type| get_type_name_from_ref(type) }
    ensure
      @function_types = old_function_types
      @function_base_return_types = old_base_return_types
      @infer_type_cache = old_infer_type_cache
      @infer_type_guarded = old_infer_type_guarded
      @infer_body_context = old_infer_body_context
      @current_class = old_current_class
      @current_method = old_current_method
      @current_def_node = old_current_def
      @infer_self_type_name = old_infer_self_type_name
      @current_method_is_class = old_current_method_is_class
      @current_typeof_locals = old_typeof_locals
      @current_typeof_local_names = old_typeof_names
      @infer_type_cache_version = old_cache_version
      @function_type_revision = old_function_type_revision
      @function_base_return_type_revision = old_base_return_type_revision
      @infer_callsite_return_stack = old_callsite_return_stack
      @infer_callsite_return_frames = old_callsite_return_frames
      @infer_callsite_return_lows = old_callsite_return_lows
      @infer_callsite_return_anchored = old_callsite_return_anchored
      @infer_callsite_return_memo = old_callsite_return_memo
      @return_infer_unproven_local_reads = old_return_unproven_reads
    end
  end
end

private def parse_bare_class_call_return_probe(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  parsed = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  converter = Adamas::HIR::AstToHir.new(
    parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source},
  )
  converter.arena = parsed.arena
  parsed.roots.each do |root|
    if node = parsed.arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    end
  end
  converter
end

private def bare_class_call_return_probe_source : String
  <<-CRYSTAL
    class BareClassCallWrongResult
    end

    class BareClassCallRightResult
    end

    class BareClassCallReturnFactory
      def self.new_internal
        new()
      end

      def self.open_internal
        new_internal()
      end

      def self.explicit_open_internal
        BareClassCallReturnFactory.new_internal()
      end

      def self.six_argument_internal(filename : String, fd : Int32, mode : Int32, blocking : Bool, encoding : String, invalid : String)
        new(filename, fd, mode, blocking, encoding, invalid)
      end

      def self.open_six_argument_internal
        six_argument_internal("file", 1, 2, true, "utf8", "strict")
      end

      def self.default_internal(filename : String = "file", fd : Int32 = 1)
        new(filename, fd)
      end

      def self.open_default_internal
        default_internal()
      end

      def self.open_named_default_internal
        default_internal(fd: 2, filename: "file")
      end

      def self.default_int_payload(value = 1)
        value
      end

      def self.default_string_payload(value = "x")
        value
      end

      def self.external_payload(label value)
        value
      end

      def self.external_payload_caller
        external_payload(label: 65_i32)
      end

      def self.echo_uint8(value : UInt8)
        value
      end

      def self.echo_uint8_external(external value : UInt8)
        value
      end

      def self.echo_uint8_positional_literal_caller
        echo_uint8(65)
      end

      def self.echo_uint8_named_literal_caller
        echo_uint8(value: 65)
      end

      def self.echo_uint8_external_literal_caller
        echo_uint8_external(external: 65)
      end

      def self.echo_uint8_runtime_caller(value : Int32)
        echo_uint8(value)
      end

      def self.echo_uint8_out_of_range_caller
        echo_uint8(300)
      end

      def self.external_default_payload(label value = "fallback")
        value
      end

      def self.external_default_actual_caller
        external_default_payload(label: 65_i32)
      end

      def self.external_default_omitted_caller
        external_default_payload()
      end

      def self.external_default_unknown_caller(value)
        external_default_payload(label: value)
      end

      def self.default_int_payload_caller
        default_int_payload()
      end

      def self.default_string_payload_caller
        default_string_payload()
      end

      def self.default_int_payload_string_actual_caller
        default_int_payload("payload")
      end

      def self.dependent_default_payload(first = 1, second = first)
        second
      end

      def self.dependent_default_payload_caller
        dependent_default_payload()
      end

      def self.dependent_default_actual_payload_caller
        dependent_default_payload("payload")
      end

      def self.named_only_payload(*, first, second)
        second
      end

      def self.named_only_payload_caller
        named_only_payload(second: "named-only", first: 1)
      end

      def self.named_reordered_payload(first, second)
        second
      end

      def self.named_reordered_payload_caller
        named_reordered_payload(second: "named-reordered", first: 1)
      end

      def self.unknown_default_payload(value = 1)
        value
      end

      def self.unknown_default_payload_caller(value)
        unknown_default_payload(value)
      end

      def self.annotated_payload(value = "exact") : String
        value
      end

      def self.annotated_payload_caller
        annotated_payload()
      end

      def self.pick(value : Int32)
        BareClassCallWrongResult.new()
      end

      def self.pick(value : String)
        BareClassCallRightResult.new()
      end

      def self.pick_int
        pick(1)
      end

      def self.pick_string
        pick("one")
      end

      def self.pick_unknown(value)
        pick(value)
      end

      def self.pick_named_annotated(value : Int32) : BareClassCallWrongResult
        BareClassCallWrongResult.new()
      end

      def self.pick_named_annotated(value : String) : BareClassCallRightResult
        BareClassCallRightResult.new()
      end

      def self.pick_named_annotated_string
        pick_named_annotated(value: "one")
      end

      def self.pick_named_inferred(value : Int32)
        BareClassCallWrongResult.new()
      end

      def self.pick_named_inferred(value : String)
        BareClassCallRightResult.new()
      end

      def self.pick_named_inferred_string
        pick_named_inferred(value: "one")
      end

      def self.pick_named_unknown(value)
        pick_named_annotated(value: value)
      end

      def self.same_name
        new()
      end

      def same_name
        BareClassCallWrongResult.new()
      end

      def self.same_name_caller
        same_name()
      end

      def self.cycle_a
        cycle_b()
      end

      def self.cycle_b
        cycle_a()
      end

      def self.cycle_caller
        cycle_a()
      end
    end

    class BareClassCallParentFactory
      def self.new_internal
        new()
      end
    end

    class BareClassCallChildFactory < BareClassCallParentFactory
      def self.open_internal
        new_internal()
      end
    end
  CRYSTAL
end

describe "bare class call return inference with cold caches" do
  it "infers a bare no-argument class helper ending in new from an active caller body" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "open_internal", "new_internal",
    ).should eq("BareClassCallReturnFactory")
  end

  it "infers an explicit receiver call with the same cold helper caches" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "explicit_open_internal", "new_internal",
    ).should eq("BareClassCallReturnFactory")
  end

  it "infers a six-argument helper whose body ends in new" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "open_six_argument_internal", "six_argument_internal",
    ).should eq("BareClassCallReturnFactory")
  end

  it "infers omitted and named default arguments" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "open_default_internal", "default_internal",
    ).should eq("BareClassCallReturnFactory")
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "open_named_default_internal", "default_internal",
    ).should eq("BareClassCallReturnFactory")
  end

  it "infers default payload types and actual arguments without a return cache" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "default_int_payload_caller", "default_int_payload",
    ).should eq("Int32")
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "default_string_payload_caller", "default_string_payload",
    ).should eq("String")
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "default_int_payload_string_actual_caller", "default_int_payload",
    ).should eq("String")
  end

  it "maps external labels to internal parameter names and keeps actuals over defaults" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "external_payload_caller", "external_payload",
    ).should eq("Int32")
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "external_default_actual_caller", "external_default_payload",
    ).should eq("Int32")
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "external_default_omitted_caller", "external_default_payload",
    ).should eq("String")
  end

  it "preserves validated UInt8 literal conversions in selected body inference" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "echo_uint8_positional_literal_caller", "echo_uint8",
    ).should eq("UInt8")
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "echo_uint8_named_literal_caller", "echo_uint8",
    ).should eq("UInt8")
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "echo_uint8_external_literal_caller", "echo_uint8_external",
    ).should eq("UInt8")
  end

  it "keeps UInt8 literal admission bounded by representability and runtime domain" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "echo_uint8_out_of_range_caller", "echo_uint8",
    ).should be_nil
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "echo_uint8_runtime_caller", "echo_uint8",
      caller_type_bindings: {"value" => "Int32"},
    ).should be_nil
  end

  it "does not use an external-label default when its supplied actual is unknown" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "external_default_unknown_caller", "external_default_payload",
    ).should be_nil
  end

  it "uses an earlier actual or default for a dependent later default" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "dependent_default_payload_caller", "dependent_default_payload",
    ).should eq("Int32")
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "dependent_default_actual_payload_caller", "dependent_default_payload",
    ).should eq("String")
  end

  it "binds named-only and reordered named arguments by name" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "named_only_payload_caller", "named_only_payload",
    ).should eq("String")
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "named_reordered_payload_caller", "named_reordered_payload",
    ).should eq("String")
  end

  it "does not substitute an omitted default for an unknown supplied value" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "unknown_default_payload_caller", "unknown_default_payload",
    ).should be_nil
  end

  it "retains a selected explicit return annotation with a cold cache" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "annotated_payload_caller", "annotated_payload",
    ).should eq("String")
  end

  it "selects same-arity class overloads by argument type even with a wrong base cache" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "pick_int", "pick",
    ).should eq("BareClassCallWrongResult")
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "pick_string", "pick",
      seed_base_return_type: "BareClassCallWrongResult",
    ).should eq("BareClassCallRightResult")
  end

  it "does not resolve a class-method bare call through a same-name instance cache" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "same_name_caller", "same_name",
      seed_instance_base_return_type: "BareClassCallWrongResult",
    ).should eq("BareClassCallReturnFactory")
  end

  it "uses the requested subclass as the result of an inherited factory" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallChildFactory", "open_internal", "new_internal",
      helper_owner_name: "BareClassCallParentFactory",
    ).should eq("BareClassCallChildFactory")
  end

  it "cuts a recursive class-method return cycle without inventing a type" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "cycle_caller", "cycle_a",
      additional_helper_methods: ["cycle_b"],
    ).should be_nil
  end

  it "keeps an ambiguous overload unknown when the caller argument is unknown" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "pick_unknown", "pick",
    ).should be_nil
  end

  it "selects annotated and inferred overloads from named actual types" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "pick_named_annotated_string", "pick_named_annotated",
    ).should eq("BareClassCallRightResult")
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "pick_named_inferred_string", "pick_named_inferred",
    ).should eq("BareClassCallRightResult")
  end

  it "keeps named overloads unresolved when the named actual type is unknown" do
    converter = parse_bare_class_call_return_probe(bare_class_call_return_probe_source)
    converter.__test_bare_class_call_return_with_cold_cache(
      "BareClassCallReturnFactory", "pick_named_unknown", "pick_named_annotated",
    ).should be_nil
  end
end
