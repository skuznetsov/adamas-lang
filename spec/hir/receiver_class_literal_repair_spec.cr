require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_repair_receiver_bound_call_targets : Nil
    repair_receiver_bound_call_targets
  end

  def __test_registered_name_for_logical_def(
    base_name : String,
    node : Adamas::Compiler::Frontend::DefNode,
    preferred_name : String = "",
  ) : String?
    registered_name_for_logical_def(base_name, node, preferred_name)
  end

  def __test_receiver_repair_call_arg_matches_param?(
    arg_type_name : String,
    param_type_name : String,
  ) : Bool
    arg_type = type_ref_for_name(arg_type_name)
    param_type = type_ref_for_name(param_type_name)
    param_type = create_union_type(param_type_name) if param_type == Adamas::HIR::TypeRef::VOID
    receiver_repair_call_arg_matches_param?(arg_type, param_type)
  end

  def __test_forget_receiver_function_shape(name : String, base_name : String) : Nil
    if definition = @function_defs[name]?
      @function_defs[base_name] ||= definition
    end
    if arena = @function_def_arenas[name]?
      @function_def_arenas[base_name] ||= arena
    end
    if function_type = @function_types[name]?
      @function_types[base_name] ||= function_type
    end
    @module.remove_function(name)
    @function_defs.delete(name)
    @function_types.delete(name)
    @function_lowering_states.delete(name)
  end

  def __test_receiver_repair_overloads(base_name : String) : Array(String)
    function_def_overloads(base_name).dup
  end

  def __test_function_def_accepts_receiver_shape?(
    function_name : String,
    arg_type_names : Array(String),
  ) : Bool
    definition = @function_defs[function_name]?
    return false unless definition
    function_def_accepts_call_shape?(
      function_name,
      definition,
      arg_type_names.map { |name| type_ref_for_name(name) },
      false,
      false,
      nil,
    )
  end

  def __test_register_receiver_repair_source_shape?(
    target_name : String,
    base_name : String,
    arg_type_names : Array(String),
  ) : Bool
    register_receiver_repair_source_shape?(
      target_name,
      base_name,
      arg_type_names.map { |name| type_ref_for_name(name) },
    )
  end

  def __test_set_receiver_function_return_type(
    name : String,
    type_name : String,
  ) : Nil
    type_ref = type_ref_for_name(type_name)
    raise "test type not found: #{type_name}" if type_ref == Adamas::HIR::TypeRef::VOID
    function = @module.function_by_name(name)
    raise "test function not found: #{name}" unless function
    function.return_type = type_ref
    @function_types[name] = type_ref
  end

  def __test_backend_synthesized_method_return_contract(name : String) : Adamas::HIR::TypeRef?
    backend_synthesized_method_return_contract(name)
  end

  def __test_receiver_repair_fallback_satisfied?(
    exact_target : String,
    fallback_base : String,
    owner : String,
    arg_type_names : Array(String),
    has_block : Bool = false,
  ) : Bool
    request = ReceiverRepairFallback.new(
      exact_target,
      fallback_base,
      owner,
      arg_type_names.map { |name| type_ref_for_name(name) },
      has_block,
      false,
      false,
      "Test#caller",
      UInt32::MAX,
      false,
      nil,
    )
    receiver_repair_fallback_satisfied?(request)
  end

  def __test_receiver_repair_strict_target_expected?(
    exact_target : String,
    fallback_base : String,
    owner : String,
    arg_type_names : Array(String),
    has_block : Bool = false,
  ) : Bool
    request = ReceiverRepairFallback.new(
      exact_target,
      fallback_base,
      owner,
      arg_type_names.map { |name| type_ref_for_name(name) },
      has_block,
      false,
      false,
      "Test#caller",
      UInt32::MAX,
      false,
      nil,
    )
    receiver_repair_strict_target_expected?(request)
  end

  def __test_has_named_call_shape(
    function_name : String,
    value_id : Adamas::HIR::ValueId,
  ) : Bool
    !named_call_shape_for(function_name, value_id).nil?
  end

  def __test_remove_hir_function(name : String) : Bool
    remove_hir_function(name)
  end

  def __test_lower_function_if_needed(name : String) : Nil
    lower_function_if_needed(name)
  end

  def __test_force_lower_function_for_return_type(name : String) : Bool
    force_lower_function_for_return_type(name)
  end

  def __test_reset_function_lowering_state(name : String) : Nil
    clear_function_state(name)
  end

  def __test_rekey_receiver_repair_request_to_canonical_body(
    exact_target : String,
    fallback_base : String,
    owner : String,
    arg_type_names : Array(String),
    caller : String,
    has_splat : Bool = false,
  ) : Bool
    call_id = UInt32::MAX
    if caller_function = @module.function_by_name(caller)
      caller_function.blocks.each do |block|
        if call = block.instructions
             .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
             .find { |instruction| instruction.method_name == exact_target }
          call_id = call.id
          break
        end
      end
    end
    named_shape = call_id == UInt32::MAX ? nil : named_call_shape_for(caller, call_id)
    request = ReceiverRepairFallback.new(
      exact_target,
      fallback_base,
      owner,
      arg_type_names.map { |name| type_ref_for_name(name) },
      false,
      has_splat,
      false,
      caller,
      call_id,
      !named_shape.nil?,
      named_shape.try(&.names),
    )
    rekey_receiver_repair_request_to_canonical_body(request)
  end

  def __test_retained_function_enum_name(
    function_name : String,
    value_id : Adamas::HIR::ValueId,
  ) : String?
    @function_enum_value_types[function_name]?.try(&.[value_id]?)
  end

  def __test_collected_function_value_type_name(
    function_name : String,
    value_id : Adamas::HIR::ValueId,
  ) : String
    function = @module.function_by_name(function_name)
    raise "test function not found: #{function_name}" unless function
    type_ref = collect_function_value_types(function.not_nil!)[value_id]? ||
               Adamas::HIR::TypeRef::VOID
    get_type_name_from_ref(type_ref)
  end

  def __test_type_name(type_ref : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type_ref)
  end

  def __test_block_param_types_for_call(
    base_method_name : String,
    mangled_method_name : String,
    receiver_name : String,
    arg_type_names : Array(String),
  ) : Array(String)?
    receiver_type = type_ref_for_name(receiver_name)
    arg_types = arg_type_names.map { |name| type_ref_for_name(name) }
    block_param_types_for_call(
      base_method_name,
      mangled_method_name,
      receiver_type,
      arg_types,
    ).try(&.map { |type_ref| get_type_name_from_ref(type_ref) })
  end

  def __test_preserves_annotated_union_param_for_shared_arity?(
    full_name_override : String?,
    type_annotation : String?,
    type_name : String,
  ) : Bool
    type_ref = type_ref_for_name(type_name)
    type_ref = create_union_type(type_name) if type_ref == Adamas::HIR::TypeRef::VOID
    preserve_annotated_union_param_for_shared_arity?(
      full_name_override,
      type_annotation,
      type_ref,
    )
  end

  def __test_prefers_inferred_union_type?(
    current_name : String,
    inferred_name : String,
  ) : Bool
    prefer_inferred_union_type?(current_name, inferred_name)
  end

  def __test_method_name_codec_exact_callsite_name?(
    requested_name : String,
    base_name : String,
    arg_type_names : Array(String),
    has_block : Bool = false,
  ) : Bool
    arg_types = arg_type_names.map do |type_name|
      type_ref = type_ref_for_name(type_name)
      type_ref = create_union_type(type_name) if type_ref == Adamas::HIR::TypeRef::VOID && type_name.includes?('|')
      raise "test type not found: #{type_name}" if type_ref == Adamas::HIR::TypeRef::VOID
      type_ref
    end
    method_name_codec_exact_callsite_name?(
      requested_name,
      base_name,
      arg_types,
      has_block,
    )
  end

end

private def parse_receiver_repair_source(
  code : String,
  source_backed : Bool = false,
) : {Adamas::HIR::AstToHir, Array(Adamas::HIR::Function)}
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  ).parse_program
  converter = if source_backed
                Adamas::HIR::AstToHir.new(
                  result.arena,
                  sources_by_arena: {result.arena.object_id.to_u64 => code},
                )
              else
                Adamas::HIR::AstToHir.new(result.arena)
              end
  converter.arena = result.arena

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  enums = [] of Adamas::Compiler::Frontend::EnumNode
  defs = [] of Adamas::Compiler::Frontend::DefNode
  result.roots.each do |root_id|
    case node = result.arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      modules << node
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::EnumNode
      enums << node
    when Adamas::Compiler::Frontend::DefNode
      defs << node
    end
  end

  enums.each { |node| converter.register_enum(node) }
  modules.each { |node| converter.register_module(node) }
  classes.each { |node| converter.register_class(node) }
  defs.each { |node| converter.register_function(node) }
  modules.each { |node| converter.lower_module(node) }
  classes.each { |node| converter.lower_class(node) }
  defs.each { |node| converter.lower_def(node) }

  {converter, converter.module.functions}
end

private def parse_class_with_corrupt_return_slice(
  code : String,
  method_name : String,
  corrupt_return_type : Slice(UInt8)?,
  corrupt_parameter_types : Bool = false,
  source_backed_registration : Bool = true,
) : {Adamas::HIR::AstToHir, Array(Adamas::HIR::Function)}
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  ).parse_program
  original_class = result.roots.compact_map do |root_id|
    result.arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
  end.first
  original_body = original_class.body.not_nil!
  replaced = false
  repaired_body = original_body.map do |member_id|
    member = result.arena[member_id]
    unless member.is_a?(Adamas::Compiler::Frontend::DefNode)
      next member_id
    end
    name = String.new(member.name)
    unless name == method_name
      next member_id
    end

    replaced = true
    repaired_params = member.params.not_nil!.map_with_index do |param, index|
      next param unless corrupt_parameter_types && index > 0 && param.type_annotation

      Adamas::Compiler::Frontend::Parameter.new(
        param.name,
        param.external_name,
        nil,
        param.default_value,
        param.span,
        param.name_span,
        param.external_name_span,
        nil,
        param.default_span,
        param.is_splat,
        param.is_double_splat,
        param.is_block,
        param.is_instance_var,
      )
    end
    result.arena.add_typed(
      Adamas::Compiler::Frontend::DefNode.new(
        member.span,
        member.name,
        repaired_params,
        corrupt_return_type,
        member.body,
        member.is_abstract,
        member.visibility,
        member.receiver,
      )
    )
  end
  raise "method not found: #{method_name}" unless replaced

  repaired_class = Adamas::Compiler::Frontend::ClassNode.new(
    original_class.span,
    original_class.name,
    original_class.super_name,
    repaired_body,
    original_class.is_abstract,
    original_class.is_struct,
    original_class.is_union,
    original_class.type_params,
    original_class.absolute,
  )
  sources = {result.arena.object_id.to_u64 => code}
  converter = if source_backed_registration
                Adamas::HIR::AstToHir.new(result.arena, sources_by_arena: sources)
              else
                Adamas::HIR::AstToHir.new(result.arena)
              end
  converter.arena = result.arena
  converter.register_class(original_class)
  converter.bootstrap_bind_source_maps(
    {} of UInt64 => String,
    {} of UInt64 => String,
  )
  converter.lower_class(repaired_class)
  {converter, converter.module.functions}
end

private def replace_with_stale_type_literal_receiver(
  converter : Adamas::HIR::AstToHir,
  function : Adamas::HIR::Function,
  original : Adamas::HIR::Call,
  receiver_type_name : String,
  stale_method_name : String,
  virtual : Bool,
) : Adamas::HIR::Call
  block = function.blocks.find { |candidate| candidate.instructions.includes?(original) }
  raise "call block not found" unless block
  call_index = block.instructions.index(original)
  raise "call index not found" unless call_index
  receiver_type_index = converter.module.types.index { |type| type.name == receiver_type_name }
  raise "receiver type not found: #{receiver_type_name}" unless receiver_type_index
  receiver_type = Adamas::HIR::TypeRef.new(
    Adamas::HIR::TypeRef::FIRST_USER_TYPE + receiver_type_index.to_u32
  )
  stale_receiver = Adamas::HIR::Literal.new(
    function.next_value_id,
    receiver_type,
    nil,
  )
  block.instructions.insert(call_index, stale_receiver)
  stale = Adamas::HIR::Call.with_receiver_virtual(
    original.id,
    original.type,
    stale_receiver.id,
    stale_method_name,
    original.args,
    virtual,
  )
  block.instructions[call_index + 1] = stale
  stale
end

describe "block parameter owner identity" do
  it "resolves a short block annotation in the callee definition namespace" do
    converter, _ = parse_receiver_repair_source(<<-CRYSTAL)
      struct Symbol
      end

      module OwnerScope
        abstract class Symbol
          getter node_id : UInt32
        end

        class Table
          def each_local_symbol(&block : String, Symbol ->)
          end
        end
      end

      def read_node_id(table : OwnerScope::Table)
        table.each_local_symbol do |_name, symbol|
          symbol.node_id
        end
      end
    CRYSTAL

    converter.__test_block_param_types_for_call(
      "OwnerScope::Table#each_local_symbol",
      "OwnerScope::Table#each_local_symbol",
      "OwnerScope::Table",
      [] of String,
    ).should eq(["String", "OwnerScope::Symbol"])

    node_id_calls = converter.module.functions.flat_map(&.blocks).flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| call.method_name.ends_with?("#node_id") }
      .map(&.method_name)
    node_id_calls.should contain("OwnerScope::Symbol#node_id")
    node_id_calls.should_not contain("Symbol#node_id")
  end

  it "keeps the included module namespace for short block annotations" do
    converter, _ = parse_receiver_repair_source(<<-CRYSTAL)
      class Local
      end

      module IncludedOwner
        class Local
          getter value : Int32
        end

        def each(&block : Local ->)
        end
      end

      class IncludedTable
        include IncludedOwner
      end

      def read_value(table : IncludedTable)
        table.each do |item|
          item.value
        end
      end
    CRYSTAL

    converter.__test_block_param_types_for_call(
      "IncludedTable#each",
      "IncludedTable#each",
      "IncludedTable",
      [] of String,
    ).should eq(["IncludedOwner::Local"])

    value_calls = converter.module.functions.flat_map(&.blocks).flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| call.method_name.ends_with?("#value") }
      .map(&.method_name)
    value_calls.should contain("IncludedOwner::Local#value")
    value_calls.should_not contain("Local#value")
  end
end

describe "receiver-bound class-literal repair" do
  it "accepts a mangled call shape owned by a base primitive" do
    converter, _ = parse_receiver_repair_source("")
    fallback_base = "Pointer(Void)#fetch"
    converter.module.register_primitive(fallback_base, "pointer_fetch")

    converter.__test_receiver_repair_fallback_satisfied?(
      "Pointer(Void)#fetch$Int32_block",
      fallback_base,
      "Pointer(Void)",
      ["Int32"],
      true,
    ).should be_true
  end

  it "does not impose a new body contract on an unregistered legacy call" do
    converter, _ = parse_receiver_repair_source("")

    converter.__test_receiver_repair_strict_target_expected?(
      "Nil#[]$Int32",
      "Nil#[]",
      "Nil",
      ["Int32"],
    ).should be_false
  end

  it "keeps primitive template calls on the concrete receiver ABI" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      abstract struct Int
        def bits_set?(mask) : Bool
          (self & mask) == mask
        end
      end

      class PrimitiveTemplateCaller
        def self.test(value : Int32, mask : Int32) : Bool
          value.bits_set?(mask)
        end
      end
    CRYSTAL

    caller = functions.find { |candidate| candidate.name.starts_with?("PrimitiveTemplateCaller.test$") }
    caller.should_not be_nil
    call = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("bits_set?") }
    call.should_not be_nil
    call.not_nil!.method_name = "Int#bits_set?$arity1"
    exact_target = converter.module.create_function(
      "Int32#bits_set?$Int32",
      Adamas::HIR::TypeRef::BOOL,
    )
    if exact_target.params.empty?
      exact_target.add_param("self", Adamas::HIR::TypeRef::INT32)
      exact_target.add_param("mask", Adamas::HIR::TypeRef::INT32)
    end
    unless exact_target.blocks.any? { |block| !block.instructions.empty? }
      result = Adamas::HIR::Literal.new(
        exact_target.next_value_id,
        Adamas::HIR::TypeRef::BOOL,
        false,
      )
      exact_target.get_block(exact_target.entry_block).add(result)
      exact_target.get_block(exact_target.entry_block).terminator =
        Adamas::HIR::Return.new(result.id)
    end

    converter.__test_repair_receiver_bound_call_targets

    repaired = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("bits_set?") }
    repaired.should_not be_nil
    repaired.not_nil!.method_name.should eq("Int32#bits_set?$Int32")
    converter.module.has_function_with_body?(repaired.not_nil!.method_name).should be_true
  end

  it "preserves a registered return contract when the lowering slice is empty" do
    _, functions = parse_class_with_corrupt_return_slice(<<-CRYSTAL, "stable_name", Slice(UInt8).empty)
      class LostReturnContract
        def stable_name(value : String?) : String
          value
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.starts_with?("LostReturnContract#stable_name$") }
    function.should_not be_nil
    function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::STRING)
  end

  it "preserves a registered return contract when the lowering slice is unreadable" do
    unreadable = Slice(UInt8).new(Pointer(UInt8).new(1_u64), 1)
    _, functions = parse_class_with_corrupt_return_slice(<<-CRYSTAL, "stable_name", unreadable)
      class LostUnreadableReturnContract
        def stable_name(value : String?) : String
          value
        end
      end
    CRYSTAL

    function = functions.find do |candidate|
      candidate.name.starts_with?("LostUnreadableReturnContract#stable_name$")
    end
    function.should_not be_nil
    function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::STRING)
  end

  it "preserves a registered return contract when lowering drops the slice" do
    _, functions = parse_class_with_corrupt_return_slice(<<-CRYSTAL, "stable_name", nil)
      class LostNilReturnContract
        def stable_name(value : String?) : String
          value
        end
      end
    CRYSTAL

    function = functions.find do |candidate|
      candidate.name.starts_with?("LostNilReturnContract#stable_name$")
    end
    function.should_not be_nil
    function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::STRING)
  end

  it "records a readable raw return contract when registration has no source map" do
    _, functions = parse_class_with_corrupt_return_slice(
      <<-CRYSTAL,
        class RawReturnContract
          def stable_name(value : String?) : String
            value
          end
        end
      CRYSTAL
      "stable_name",
      nil,
      source_backed_registration: false,
    )

    function = functions.find do |candidate|
      candidate.name.starts_with?("RawReturnContract#stable_name$Nil | String")
    end
    function.should_not be_nil
    function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::STRING)
  end

  it "restores the registered signature when lowering drops parameter and return slices" do
    _, functions = parse_class_with_corrupt_return_slice(
      <<-CRYSTAL,
        class LostSignatureContract
          def stable_name(prefix : String, value : String?, id : Int32, enabled : Bool) : String
            prefix
          end
        end
      CRYSTAL
      "stable_name",
      nil,
      corrupt_parameter_types: true,
    )

    function = functions.find do |candidate|
      candidate.name.starts_with?(
        "LostSignatureContract#stable_name$String_Nil | String_Int32_Bool"
      )
    end
    function.should_not be_nil
    function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::STRING)
  end

  it "restores registered parameter types without an explicit return contract" do
    _, functions = parse_class_with_corrupt_return_slice(
      <<-CRYSTAL,
        class LostInferredSignatureContract
          def stable_name(prefix : String, value : String?, id : Int32, enabled : Bool)
            prefix
          end
        end
      CRYSTAL
      "stable_name",
      nil,
      corrupt_parameter_types: true,
    )

    function = functions.find do |candidate|
      candidate.name.starts_with?(
        "LostInferredSignatureContract#stable_name$String_Nil | String_Int32_Bool"
      )
    end
    function.should_not be_nil
  end

  it "keeps an explicit String result non-nilable at a typed call boundary" do
    converter, functions = parse_class_with_corrupt_return_slice(
      <<-CRYSTAL,
        class TransportedCallContract
          def extract(value : String?) : String
            value || ""
          end

          def record(owner : String?, name : String) : Nil
          end

          def run(owner : String?, value : String?) : Nil
            record(owner, extract(value))
          end
        end
      CRYSTAL
      "extract",
      nil,
    )
    converter.__test_repair_receiver_bound_call_targets

    run_function = functions.find do |candidate|
      candidate.name.starts_with?(
        "TransportedCallContract#run$Nil | String_Nil | String"
      )
    end
    run_function.should_not be_nil
    record_call = run_function.not_nil!.blocks
      .flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |call| call.method_name.starts_with?("TransportedCallContract#record$") }
    record_call.should_not be_nil
    record_call.not_nil!.method_name.should eq(
      "TransportedCallContract#record$Nil | String_String"
    )
  end

  it "keeps partial typed overload history isolated from a sibling initializer" do
    converter, functions = parse_receiver_repair_source(
      <<-CRYSTAL,
        struct PartialHistoryStack
        end

        class PartialHistoryThread
          property handler : Pointer(Void) = Pointer(Void).null
        end

        class PartialHistoryOwner
          def initialize(name : String?, stack : PartialHistoryStack)
          end

          def initialize(stack : Pointer(Void), thread)
            thread.handler = Pointer(Void).null
          end

          def self.build(stack : Pointer(Void), thread : PartialHistoryThread)
            new(stack, thread)
          end
        end
      CRYSTAL
      source_backed: true,
    )

    initializer = functions.find do |candidate|
      candidate.name ==
        "PartialHistoryOwner#initialize$Pointer(Void)_PartialHistoryThread"
    end
    initializer.should_not be_nil
    initializer.not_nil!.params
      .map { |param| converter.__test_type_name(param.type) }
      .should eq([
        "PartialHistoryOwner",
        "Pointer(Void)",
        "PartialHistoryThread",
      ])
  end

  it "fails closed when equal spans cannot distinguish registered signatures" do
    char_result = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(<<-CRYSTAL)
        def stable_name(value : Char)
          value
        end
      CRYSTAL
    ).parse_program
    bool_result = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(<<-CRYSTAL)
        def stable_name(value : Bool)
          value
        end
      CRYSTAL
    ).parse_program
    char_def = char_result.arena[char_result.roots.first]
      .as(Adamas::Compiler::Frontend::DefNode)
    bool_def = bool_result.arena[bool_result.roots.first]
      .as(Adamas::Compiler::Frontend::DefNode)
    transported_params = bool_def.params.not_nil!.map do |param|
      Adamas::Compiler::Frontend::Parameter.new(
        param.name,
        param.external_name,
        nil,
        param.default_value,
        param.span,
        param.name_span,
        param.external_name_span,
        nil,
        param.default_span,
        param.is_splat,
        param.is_double_splat,
        param.is_block,
        param.is_instance_var,
      )
    end
    transported_bool_def = Adamas::Compiler::Frontend::DefNode.new(
      bool_def.span,
      bool_def.name,
      transported_params,
      bool_def.return_type,
      bool_def.body.try(&.dup),
      bool_def.is_abstract,
      bool_def.visibility,
      bool_def.receiver,
    )

    converter = Adamas::HIR::AstToHir.new(char_result.arena)
    converter.arena = char_result.arena
    converter.register_function(char_def)
    converter.arena = bool_result.arena
    converter.register_function(bool_def)

    converter.__test_registered_name_for_logical_def(
      "stable_name",
      bool_def,
    ).should eq("stable_name$Bool")

    # The active lowering arena can belong to another candidate (for example,
    # a caller arena). It must not be treated as proof that the transported
    # definition came from that candidate.
    converter.arena = char_result.arena
    converter.__test_registered_name_for_logical_def(
      "stable_name",
      transported_bool_def,
    ).should be_nil
    converter.__test_registered_name_for_logical_def(
      "stable_name",
      transported_bool_def,
      "stable_name$Bool",
    ).should eq("stable_name$Bool")
  end

  it "keeps registered return contracts isolated by exact overload key" do
    _, functions = parse_class_with_corrupt_return_slice(<<-CRYSTAL, "stable_name", Slice(UInt8).empty)
      class RegisteredReturnOverloads
        def stable_name(value : String?) : String
          value
        end

        def stable_name(value : Int32) : Int32
          value
        end
      end
    CRYSTAL

    string_overload = functions.find do |candidate|
      candidate.name.starts_with?("RegisteredReturnOverloads#stable_name$Nil | String")
    end
    int_overload = functions.find do |candidate|
      candidate.name.starts_with?("RegisteredReturnOverloads#stable_name$Int32")
    end
    string_overload.should_not be_nil
    int_overload.should_not be_nil
    string_overload.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::STRING)
    int_overload.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "rekeys a receiverless class-method arity target from concrete callsite types" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      module TinyGlob
        def self.compile(pattern : String) : String
          single_compile(pattern)
        end

        private def self.single_compile(glob)
          glob
        end
      end
    CRYSTAL

    caller = functions.find { |candidate| candidate.name.starts_with?("TinyGlob.compile$") }
    caller.should_not be_nil
    call = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("single_compile") }
    call.should_not be_nil
    original = call.not_nil!
    original.args.size.should eq(1)

    # Model the s2 stale target: the callsite carries String but retains the
    # shared arity symbol that was materialized with an untyped/Void parameter.
    # Class-method lowering normally leaves a synthetic type-literal receiver;
    # erase it here so this seam is specifically the receiverless dotted form.
    call_block = caller.not_nil!.blocks.find { |candidate| candidate.instructions.includes?(original) }
    call_block.should_not be_nil
    call_index = call_block.not_nil!.instructions.index(original).not_nil!
    stale = Adamas::HIR::Call.without_receiver(
      original.id,
      original.type,
      "TinyGlob.single_compile$arity1",
      original.args,
    )
    call_block.not_nil!.instructions[call_index] = stale
    original = stale
    original.has_receiver?.should be_false

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.id == original.id }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.method_name.should contain("TinyGlob.single_compile$String")
    repaired_call.not_nil!.method_name.should_not contain("$arity")
    typed = functions.find { |candidate| candidate.name == "TinyGlob.single_compile$String" }
    typed.should_not be_nil
    typed.not_nil!.params.last.type.should eq(Adamas::HIR::TypeRef::STRING)
  end

  it "materializes an unseen typed shape for an inherited arity target" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      abstract class IO
        def <<(obj : _) : self
          self
        end
      end

      class String::Builder < IO
      end

      def append_inherited(builder : String::Builder, value : String) : String::Builder
        builder << value
      end
    CRYSTAL

    caller = functions.find { |candidate| candidate.name.starts_with?("append_inherited$") }
    caller.should_not be_nil
    original = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("#<<") }
    original.should_not be_nil
    original_parent_target = original.not_nil!.method_name
    original_parent_target.should contain("IO#<<$String")

    converter.__test_forget_receiver_function_shape(
      original_parent_target,
      "IO#<<",
    )
    converter.__test_set_receiver_function_return_type(
      "String::Builder#<<$String",
      "IO",
    )
    call_block = caller.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(original.not_nil!)
    end
    call_block.should_not be_nil
    call_index = call_block.not_nil!.instructions.index(original.not_nil!).not_nil!
    stale = Adamas::HIR::Call.with_receiver_virtual(
      original.not_nil!.id,
      original.not_nil!.type,
      original.not_nil!.receiver_value,
      "IO#<<$arity1",
      original.not_nil!.args,
      false,
    )
    call_block.not_nil!.instructions[call_index] = stale

    converter.__test_repair_receiver_bound_call_targets

    repaired = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.id == stale.id }
    repaired.should_not be_nil
    repaired.not_nil!.method_name.should eq("String::Builder#<<$String")
    repaired.not_nil!.type.should eq(caller.not_nil!.params[0].type)
    wrapper = converter.module.function_by_name("String::Builder#<<$String")
    wrapper.should_not be_nil
    converter.module.has_function_with_body?(wrapper.not_nil!.name).should be_true
    wrapper.not_nil!.params[0].type.should eq(caller.not_nil!.params[0].type)
    wrapper.not_nil!.params[1].type.should eq(Adamas::HIR::TypeRef::STRING)
    wrapper.not_nil!.return_type.should eq(caller.not_nil!.params[0].type)
  end

  it "does not bypass a receiver override when repairing an ancestor arity target" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class OverrideIO
        def append(value) : self
          self
        end
      end

      class OverrideBuilder < OverrideIO
        def append(value) : self
          self
        end
      end

      def append_override(builder : OverrideBuilder, value : String) : OverrideBuilder
        builder.append(value)
      end
    CRYSTAL

    caller = functions.find { |candidate| candidate.name.starts_with?("append_override$") }
    caller.should_not be_nil
    original = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("#append") }
    original.should_not be_nil
    original.not_nil!.method_name.should eq("OverrideBuilder#append$String")

    call_block = caller.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(original.not_nil!)
    end
    call_block.should_not be_nil
    call_index = call_block.not_nil!.instructions.index(original.not_nil!).not_nil!
    stale = Adamas::HIR::Call.with_receiver_virtual(
      original.not_nil!.id,
      original.not_nil!.type,
      original.not_nil!.receiver_value,
      "OverrideIO#append$arity1",
      original.not_nil!.args,
      false,
    )
    call_block.not_nil!.instructions[call_index] = stale

    converter.__test_repair_receiver_bound_call_targets

    repaired = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.id == stale.id }
    repaired.should_not be_nil
    repaired.not_nil!.method_name.should eq("OverrideBuilder#append$String")
    converter.module.has_function_with_body?(repaired.not_nil!.method_name).should be_true
  end

  it "recovers a void-typed call producer before specializing its receiver consumer" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class VoidArgProducer
        def value : UInt64
          1_u64
        end
      end

      class VoidArgSink
        def append(value)
          value
        end
      end

      def append_void_arg(sink : VoidArgSink, producer : VoidArgProducer)
        sink.append(producer.value)
      end
    CRYSTAL

    caller = functions.find { |candidate| candidate.name.starts_with?("append_void_arg$") }
    caller.should_not be_nil
    calls = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
    producer = calls.find { |instruction| instruction.method_name.includes?("#value") }
    consumer = calls.find { |instruction| instruction.method_name.includes?("#append") }
    producer.should_not be_nil
    consumer.should_not be_nil

    producer_block = caller.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(producer.not_nil!)
    end
    producer_block.should_not be_nil
    producer_index = producer_block.not_nil!.instructions.index(producer.not_nil!).not_nil!
    void_producer = Adamas::HIR::Call.with_receiver_virtual(
      producer.not_nil!.id,
      Adamas::HIR::TypeRef::VOID,
      producer.not_nil!.receiver_value,
      producer.not_nil!.method_name,
      producer.not_nil!.args,
      producer.not_nil!.virtual,
    )
    producer_block.not_nil!.instructions[producer_index] = void_producer

    converter.__test_forget_receiver_function_shape(
      consumer.not_nil!.method_name,
      "VoidArgSink#append",
    )
    consumer_block = caller.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(consumer.not_nil!)
    end
    consumer_block.should_not be_nil
    consumer_index = consumer_block.not_nil!.instructions.index(consumer.not_nil!).not_nil!
    stale_consumer = Adamas::HIR::Call.with_receiver_virtual(
      consumer.not_nil!.id,
      consumer.not_nil!.type,
      consumer.not_nil!.receiver_value,
      "VoidArgSink#append$arity1",
      consumer.not_nil!.args,
      consumer.not_nil!.virtual,
    )
    consumer_block.not_nil!.instructions[consumer_index] = stale_consumer

    converter.__test_repair_receiver_bound_call_targets

    repaired_calls = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
    repaired_producer = repaired_calls.find { |instruction| instruction.id == void_producer.id }
    repaired_consumer = repaired_calls.find { |instruction| instruction.id == stale_consumer.id }
    repaired_producer.should_not be_nil
    repaired_consumer.should_not be_nil
    repaired_producer.not_nil!.type.should eq(Adamas::HIR::TypeRef::UINT64)
    repaired_consumer.not_nil!.method_name.should eq("VoidArgSink#append$UInt64")
    converter.module.has_function_with_body?(repaired_consumer.not_nil!.method_name).should be_true
  end

  it "recovers a void-typed call producer through a copy before specializing its consumer" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class CopiedVoidArgProducer
        def value : UInt64
          1_u64
        end
      end

      class CopiedVoidArgSink
        def append(value)
          value
        end
      end

      def append_copied_void_arg(sink : CopiedVoidArgSink, producer : CopiedVoidArgProducer)
        sink.append(producer.value)
      end
    CRYSTAL

    caller = functions.find { |candidate| candidate.name.starts_with?("append_copied_void_arg$") }
    caller.should_not be_nil
    calls = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
    producer = calls.find { |instruction| instruction.method_name.includes?("#value") }
    consumer = calls.find { |instruction| instruction.method_name.includes?("#append") }
    producer.should_not be_nil
    consumer.should_not be_nil

    producer_block = caller.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(producer.not_nil!)
    end
    producer_block.should_not be_nil
    producer_index = producer_block.not_nil!.instructions.index(producer.not_nil!).not_nil!
    void_producer = Adamas::HIR::Call.with_receiver_virtual(
      producer.not_nil!.id,
      Adamas::HIR::TypeRef::VOID,
      producer.not_nil!.receiver_value,
      producer.not_nil!.method_name,
      producer.not_nil!.args,
      producer.not_nil!.virtual,
    )
    producer_block.not_nil!.instructions[producer_index] = void_producer
    void_copy = Adamas::HIR::Copy.new(
      caller.not_nil!.next_value_id,
      Adamas::HIR::TypeRef::VOID,
      void_producer.id,
    )
    producer_block.not_nil!.instructions.insert(producer_index + 1, void_copy)

    converter.__test_forget_receiver_function_shape(
      consumer.not_nil!.method_name,
      "CopiedVoidArgSink#append",
    )
    consumer_block = caller.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(consumer.not_nil!)
    end
    consumer_block.should_not be_nil
    consumer_index = consumer_block.not_nil!.instructions.index(consumer.not_nil!).not_nil!
    stale_consumer = Adamas::HIR::Call.with_receiver_virtual(
      consumer.not_nil!.id,
      consumer.not_nil!.type,
      consumer.not_nil!.receiver_value,
      "CopiedVoidArgSink#append$arity1",
      [void_copy.id],
      consumer.not_nil!.virtual,
    )
    consumer_block.not_nil!.instructions[consumer_index] = stale_consumer

    converter.__test_repair_receiver_bound_call_targets

    repaired_values = caller.not_nil!.blocks.flat_map(&.instructions)
    repaired_copy = repaired_values.find { |instruction| instruction.id == void_copy.id }
    repaired_consumer = repaired_values
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.id == stale_consumer.id }
    repaired_copy.should_not be_nil
    repaired_consumer.should_not be_nil
    repaired_copy.not_nil!.type.should eq(Adamas::HIR::TypeRef::UINT64)
    repaired_consumer.not_nil!.method_name.should eq("CopiedVoidArgSink#append$UInt64")
    converter.module.has_function_with_body?(repaired_consumer.not_nil!.method_name).should be_true
  end

  it "recovers IO#pos from its exact backend ABI contract" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class IO
        def pos
          raise "unavailable"
        end
      end

      class IO::Buffered < IO
        def pos : Int64
          1_i64
        end
      end

      class PositionSink
        def append(value)
          value
        end
      end

      def append_io_position(sink : PositionSink, io : IO)
        sink.append(io.pos)
      end

      def read_buffered_position(io : IO::Buffered) : Int64
        io.pos
      end
    CRYSTAL

    caller = functions.find { |candidate| candidate.name.starts_with?("append_io_position$") }
    caller.should_not be_nil
    buffered_caller = functions.find { |candidate| candidate.name.starts_with?("read_buffered_position$") }
    buffered_caller.should_not be_nil
    buffered_call = buffered_caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("#pos") }
    buffered_call.should_not be_nil
    buffered_call.not_nil!.method_name.should eq("IO::Buffered#pos")
    buffered_call.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT64)
    converter.__test_backend_synthesized_method_return_contract("IO#pos")
      .should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_backend_synthesized_method_return_contract("IO#pos$arity0").should be_nil
    converter.__test_backend_synthesized_method_return_contract("IO::Buffered#pos").should be_nil

    calls = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
    producer = calls.find { |instruction| instruction.method_name == "IO#pos" }
    consumer = calls.find { |instruction| instruction.method_name.includes?("#append") }
    producer.should_not be_nil
    consumer.should_not be_nil

    producer_block = caller.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(producer.not_nil!)
    end
    producer_block.should_not be_nil
    producer_index = producer_block.not_nil!.instructions.index(producer.not_nil!).not_nil!
    void_producer = Adamas::HIR::Call.with_receiver_virtual(
      producer.not_nil!.id,
      Adamas::HIR::TypeRef::VOID,
      producer.not_nil!.receiver_value,
      producer.not_nil!.method_name,
      producer.not_nil!.args,
      producer.not_nil!.virtual,
    )
    producer_block.not_nil!.instructions[producer_index] = void_producer

    converter.__test_forget_receiver_function_shape(
      consumer.not_nil!.method_name,
      "PositionSink#append",
    )
    consumer_block = caller.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(consumer.not_nil!)
    end
    consumer_block.should_not be_nil
    consumer_index = consumer_block.not_nil!.instructions.index(consumer.not_nil!).not_nil!
    stale_consumer = Adamas::HIR::Call.with_receiver_virtual(
      consumer.not_nil!.id,
      consumer.not_nil!.type,
      consumer.not_nil!.receiver_value,
      "PositionSink#append$arity1",
      consumer.not_nil!.args,
      consumer.not_nil!.virtual,
    )
    consumer_block.not_nil!.instructions[consumer_index] = stale_consumer

    converter.__test_repair_receiver_bound_call_targets

    repaired_calls = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
    repaired_producer = repaired_calls.find { |instruction| instruction.id == void_producer.id }
    repaired_consumer = repaired_calls.find { |instruction| instruction.id == stale_consumer.id }
    repaired_producer.should_not be_nil
    repaired_consumer.should_not be_nil
    repaired_producer.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)
    repaired_consumer.not_nil!.method_name.should eq("PositionSink#append$Int32")
    converter.module.has_function_with_body?(repaired_consumer.not_nil!.method_name).should be_true
  end

  it "resolves receiver-dependent self before accepting a cached producer return type" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      abstract class VoidReturnIO
        def append(value : _) : self
          self
        end
      end

      class VoidReturnBuilder < VoidReturnIO
      end

      class ReceiverValueSink
        def consume(value)
          value
        end
      end

      def consume_builder_value(
        sink : ReceiverValueSink,
        builder : VoidReturnBuilder,
        value : String,
      )
        sink.consume(builder.append(value))
      end
    CRYSTAL

    caller = functions.find { |candidate| candidate.name.starts_with?("consume_builder_value$") }
    caller.should_not be_nil
    calls = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
    producer = calls.find { |instruction| instruction.method_name.includes?("#append") }
    consumer = calls.find { |instruction| instruction.method_name.includes?("#consume") }
    producer.should_not be_nil
    consumer.should_not be_nil

    producer_block = caller.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(producer.not_nil!)
    end
    producer_block.should_not be_nil
    producer_index = producer_block.not_nil!.instructions.index(producer.not_nil!).not_nil!
    stale_producer = Adamas::HIR::Call.with_receiver_virtual(
      producer.not_nil!.id,
      Adamas::HIR::TypeRef::VOID,
      producer.not_nil!.receiver_value,
      "VoidReturnIO#append$arity1",
      producer.not_nil!.args,
      producer.not_nil!.virtual,
    )
    producer_block.not_nil!.instructions[producer_index] = stale_producer

    converter.__test_forget_receiver_function_shape(
      consumer.not_nil!.method_name,
      "ReceiverValueSink#consume",
    )
    consumer_block = caller.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(consumer.not_nil!)
    end
    consumer_block.should_not be_nil
    consumer_index = consumer_block.not_nil!.instructions.index(consumer.not_nil!).not_nil!
    stale_consumer = Adamas::HIR::Call.with_receiver_virtual(
      consumer.not_nil!.id,
      consumer.not_nil!.type,
      consumer.not_nil!.receiver_value,
      "ReceiverValueSink#consume$arity1",
      consumer.not_nil!.args,
      consumer.not_nil!.virtual,
    )
    consumer_block.not_nil!.instructions[consumer_index] = stale_consumer

    converter.__test_repair_receiver_bound_call_targets

    repaired_calls = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
    repaired_producer = repaired_calls.find { |instruction| instruction.id == stale_producer.id }
    repaired_consumer = repaired_calls.find { |instruction| instruction.id == stale_consumer.id }
    repaired_producer.should_not be_nil
    repaired_consumer.should_not be_nil
    repaired_producer.not_nil!.type.should eq(caller.not_nil!.params[1].type)
    repaired_consumer.not_nil!.method_name.should eq("ReceiverValueSink#consume$VoidReturnBuilder")
    converter.module.has_function_with_body?(repaired_consumer.not_nil!.method_name).should be_true
  end

  it "fails closed for unknown arity targets while separating concrete callsite types" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      module TinyGlob
        def self.string_call(pattern : String) : String
          single_compile(pattern)
        end

        def self.int_call(value : Int32) : Int32
          single_compile(value)
        end

        def self.unknown_call(pattern : String) : String
          single_compile(pattern)
        end

        private def self.single_compile(glob)
          glob
        end
      end
    CRYSTAL

    stale_calls = {
      "string_call" => "String",
      "int_call"    => "Int32",
    }
    stale_calls.each do |caller_name, expected_type|
      caller = functions.find { |candidate| candidate.name.starts_with?("TinyGlob.#{caller_name}$") }
      caller.should_not be_nil
      call = caller.not_nil!.blocks.flat_map(&.instructions)
        .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
        .find { |instruction| instruction.method_name.includes?("single_compile") }
      call.should_not be_nil
      original = call.not_nil!
      call_block = caller.not_nil!.blocks.find { |candidate| candidate.instructions.includes?(original) }
      call_block.should_not be_nil
      call_index = call_block.not_nil!.instructions.index(original).not_nil!
      call_block.not_nil!.instructions[call_index] = Adamas::HIR::Call.without_receiver(
        original.id,
        original.type,
        "TinyGlob.single_compile$arity1",
        original.args,
      )
    end

    unknown_caller = functions.find { |candidate| candidate.name.starts_with?("TinyGlob.unknown_call$") }
    unknown_caller.should_not be_nil
    unknown = unknown_caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("single_compile") }
    unknown.should_not be_nil
    unknown_original = unknown.not_nil!
    unknown_block = unknown_caller.not_nil!.blocks.find { |candidate| candidate.instructions.includes?(unknown_original) }
    unknown_block.should_not be_nil
    unknown_index = unknown_block.not_nil!.instructions.index(unknown_original).not_nil!
    unknown_block.not_nil!.instructions[unknown_index] = Adamas::HIR::Call.without_receiver(
      unknown_original.id,
      unknown_original.type,
      "TinyGlob.missing$arity1",
      unknown_original.args,
    )

    converter.__test_repair_receiver_bound_call_targets

    string_call = functions.find { |candidate| candidate.name.starts_with?("TinyGlob.string_call$") }.not_nil!
    # Locate by the rewritten symbol rather than relying on a particular local id.
    string_call.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .any? { |instruction| instruction.method_name == "TinyGlob.single_compile$String" }
      .should be_true

    int_call = functions.find { |candidate| candidate.name.starts_with?("TinyGlob.int_call$") }.not_nil!
    int_call.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .any? { |instruction| instruction.method_name == "TinyGlob.single_compile$Int32" }
      .should be_true

    unknown_caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .any? { |instruction| instruction.method_name == "TinyGlob.missing$arity1" }
      .should be_true
  end

  it "keeps backend_class.remove_impl on the class-method separator" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class FileDescriptor
      end

      class Socket
      end

      abstract class Polling
        def self.remove_impl(file_descriptor : FileDescriptor) : Nil
          nil
        end

        def self.remove_impl(socket : Socket) : Nil
          nil
        end
      end

      class EventLoop
        def self.backend_class
          Polling
        end

        def self.remove(file_descriptor : FileDescriptor) : Nil
          backend_class.remove_impl(file_descriptor)
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.starts_with?("EventLoop.remove$") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("remove_impl") }
    call.should_not be_nil
    backend_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("backend_class") }
    backend_call.should_not be_nil
    backend_call.not_nil!.has_receiver?.should be_false
    backend_call.not_nil!.method_name.should start_with("EventLoop.backend_class")
    backend_block = function.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(backend_call.not_nil!)
    end
    backend_block.should_not be_nil
    backend_index = backend_block.not_nil!.instructions.index(backend_call.not_nil!).not_nil!
    backend = backend_call.not_nil!
    backend_block.not_nil!.instructions[backend_index] = Adamas::HIR::Call.without_receiver(
      backend.id, Adamas::HIR::TypeRef::STRING, backend.method_name, backend.args
    )
    # Model the s2 HIR stale-owner shape observed before receiver repair.
    call.not_nil!.method_name = "String#remove_impl$FileDescriptor"

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("remove_impl") }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_false
    repaired_call.not_nil!.method_name.should start_with("Polling.remove_impl")
  end

  it "keeps an inherited bare class identifier on the class-method separator" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      abstract class ParentPolling
        def self.backend_class
          PollingTarget
        end
      end

      abstract class PollingTarget
        def self.remove_impl(value : Int32) : Nil
          nil
        end
      end

      abstract class ChildPolling < ParentPolling
        def self.remove(value : Int32) : Nil
          backend_class.remove_impl(value)
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.starts_with?("ChildPolling.remove$") }
    function.should_not be_nil
    backend_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("backend_class") }
    backend_call.should_not be_nil
    backend_call.not_nil!.has_receiver?.should be_false
    backend_call.not_nil!.method_name.should start_with("ChildPolling.backend_class")
    inherited_target = converter.module.function_by_name(backend_call.not_nil!.method_name)
    inherited_target.should_not be_nil
    inherited_target.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
  end

  it "keeps a real instance producer receiver-bound" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class Service
        def self.make : Service
          Service.new
        end

        def ping : Nil
          nil
        end
      end

      class Caller
        def self.use : Nil
          Service.make.ping
        end
      end
    CRYSTAL

    converter.__test_repair_receiver_bound_call_targets

    function = functions.find { |candidate| candidate.name.starts_with?("Caller.use$") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("ping") }
    call.should_not be_nil
    call.not_nil!.has_receiver?.should be_true
    call.not_nil!.method_name.should contain("Service#ping")
  end

  it "keeps a bare instance identifier receiver-bound" do
    _, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class Relay
        def ping : Nil
          nil
        end

        def relay : Nil
          ping
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.starts_with?("Relay#relay") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("ping") }
    call.should_not be_nil
    call.not_nil!.has_receiver?.should be_true
    call.not_nil!.method_name.should start_with("Relay#ping")
  end

  it "separates same-name bare instance and class identifiers" do
    _, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class SplitRelay
        def ping : Nil
          nil
        end

        def self.ping : Nil
          nil
        end

        def relay : Nil
          ping
        end

        def self.run : Nil
          ping
        end
      end
    CRYSTAL

    instance_function = functions.find { |candidate| candidate.name.starts_with?("SplitRelay#relay") }
    class_function = functions.find { |candidate| candidate.name.starts_with?("SplitRelay.run") }
    instance_function.should_not be_nil
    class_function.should_not be_nil

    instance_call = instance_function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("ping") }
    class_call = class_function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("ping") }
    instance_call.should_not be_nil
    class_call.should_not be_nil
    instance_call.not_nil!.has_receiver?.should be_true
    instance_call.not_nil!.method_name.should start_with("SplitRelay#ping")
    class_call.not_nil!.has_receiver?.should be_false
    class_call.not_nil!.method_name.should start_with("SplitRelay.ping")
  end

  it "does not alias a class-only method into an instance identifier" do
    _, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class ClassOnlyRelay
        def self.ping : Nil
          nil
        end

        def relay : Nil
          ping
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.starts_with?("ClassOnlyRelay#relay") }
    function.should_not be_nil
    function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .none? { |instruction| instruction.method_name.includes?("ping") }
      .should be_true
  end

  it "does not alias a class-only method into an explicit self call" do
    _, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class ExplicitClassOnlyRelay
        def self.ping : Nil
          nil
        end

        def relay : Nil
          self.ping
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.starts_with?("ExplicitClassOnlyRelay#relay") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("ping") }
    call.should_not be_nil
    call.not_nil!.has_receiver?.should be_true
    call.not_nil!.method_name.should start_with("ExplicitClassOnlyRelay#ping")
    call.not_nil!.method_name.should_not start_with("ExplicitClassOnlyRelay.ping")
  end

  it "does not alias a parent class method into an instance super call" do
    _, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class ParentClassOnlyRelay
        def self.ping(value : Int32) : Nil
          nil
        end
      end

      class ChildInstanceRelay < ParentClassOnlyRelay
        def ping(value : Int32) : Nil
          super(value)
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.starts_with?("ChildInstanceRelay#ping$") }
    function.should_not be_nil
    calls = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
    calls.none? { |instruction| instruction.method_name.starts_with?("ParentClassOnlyRelay.ping") }
      .should be_true
    functions.none? { |candidate| candidate.name.starts_with?("ParentClassOnlyRelay.ping") && candidate.name.includes?("_super") }
      .should be_true
  end

  it "rekeys a stale concrete suffix to the receiver call's current union shape" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class AstArena
      end

      class PageArena
      end

      class VirtualArena
      end

      def append_arena(
        arenas : Array(AstArena | PageArena | VirtualArena),
        arena : AstArena | PageArena | VirtualArena,
      )
        arenas.push(arena)
      end
    CRYSTAL

    caller = functions.find { |candidate| candidate.name.starts_with?("append_arena$") }
    caller.should_not be_nil
    original = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("#push") }
    original.should_not be_nil
    correct_name = original.not_nil!.method_name
    correct_name.should contain("$AstArena | PageArena | VirtualArena")
    correct_target = converter.module.create_function(correct_name, original.not_nil!.type)
    marker = Adamas::HIR::Literal.new(
      correct_target.next_value_id,
      Adamas::HIR::TypeRef::NIL,
      nil,
    )
    correct_target.get_block(correct_target.entry_block).add(marker)

    call_block = caller.not_nil!.blocks.find { |candidate| candidate.instructions.includes?(original.not_nil!) }
    call_block.should_not be_nil
    call_index = call_block.not_nil!.instructions.index(original.not_nil!).not_nil!
    stale = Adamas::HIR::Call.with_receiver_virtual(
      original.not_nil!.id,
      original.not_nil!.type,
      original.not_nil!.receiver_value,
      "#{original.not_nil!.method_name.split('$').first}$AstArena",
      original.not_nil!.args,
      false,
    )
    call_block.not_nil!.instructions[call_index] = stale

    converter.__test_repair_receiver_bound_call_targets

    repaired = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.id == stale.id }
    repaired.should_not be_nil
    repaired.not_nil!.method_name.should eq(correct_name)
    converter.module.has_function_with_body?(repaired.not_nil!.method_name).should be_true
  end

  it "materializes an unseen concrete shape from a compatible union definition" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      module CompatibleRepairEnumerable(T)
      end

      class CompatibleRepairArgs
        include CompatibleRepairEnumerable(String)
      end

      class CompatibleRepairIO
      end

      class CompatibleRepairMemory < CompatibleRepairIO
      end

      class CompatibleRepairRedirect
      end

      class CompatibleRepairSink
        alias Stdio = CompatibleRepairIO | CompatibleRepairRedirect

        def store(
          args : CompatibleRepairEnumerable(String)?,
          value : Stdio,
        )
          value
        end


        def ambiguous_store(value : CompatibleRepairIO)
          value
        end

        def ambiguous_store(value : Stdio)
          value
        end
      end

      def store_compatible_memory(
        sink : CompatibleRepairSink,
        args : CompatibleRepairArgs,
        value : CompatibleRepairMemory,
      )
        sink.store(args, value)
      end
    CRYSTAL

    caller = functions.find do |candidate|
      candidate.name.starts_with?("store_compatible_memory$")
    end
    caller.should_not be_nil
    original = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.starts_with?("CompatibleRepairSink#store$") }
    original.should_not be_nil
    base_name = "CompatibleRepairSink#store"
    current_name = original.not_nil!.method_name
    source_name = converter.__test_receiver_repair_overloads(base_name).find do |name|
      name.includes?("CompatibleRepairEnumerable(String)") &&
        name.includes?("CompatibleRepairIO | CompatibleRepairRedirect")
    end
    source_name.should_not be_nil
    converter.__test_function_def_accepts_receiver_shape?(
      source_name.not_nil!,
      ["Nil", "CompatibleRepairMemory"],
    ).should be_true
    converter.__test_function_def_accepts_receiver_shape?(
      source_name.not_nil!,
      ["CompatibleRepairArgs", "CompatibleRepairMemory"],
    ).should be_true

    ambiguous_base = "CompatibleRepairSink#ambiguous_store"
    ambiguous_target = "#{ambiguous_base}$CompatibleRepairMemory"
    converter.__test_register_receiver_repair_source_shape?(
      ambiguous_target,
      ambiguous_base,
      ["CompatibleRepairMemory"],
    ).should be_false
    converter.module.has_function?(ambiguous_target).should be_false
    converter.__test_forget_receiver_function_shape(
      current_name,
      base_name,
    )

    call_block = caller.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(original.not_nil!)
    end
    call_block.should_not be_nil
    call_index = call_block.not_nil!.instructions.index(original.not_nil!).not_nil!
    stale = Adamas::HIR::Call.with_receiver_virtual(
      original.not_nil!.id,
      original.not_nil!.type,
      original.not_nil!.receiver_value,
      "#{base_name}$Nil_CompatibleRepairRedirect",
      original.not_nil!.args,
      false,
    )
    call_block.not_nil!.instructions[call_index] = stale

    converter.__test_repair_receiver_bound_call_targets

    repaired = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.id == stale.id }
    repaired.should_not be_nil
    repaired.not_nil!.method_name.should eq(current_name)
    converter.module.has_function_with_body?(repaired.not_nil!.method_name).should be_true
  end

  it "materializes a concrete receiver demand whose definition canonicalizes to a union parameter" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class CanonicalAstArena
      end

      class CanonicalPageArena
      end

      class CanonicalVirtualArena
      end

      class CanonicalArenaSink(T)
        def append(value)
          push(value)
        end

        def push(value : T)
          value
        end
      end

      def append_concrete_arena(
        arenas : CanonicalArenaSink(CanonicalAstArena | CanonicalPageArena | CanonicalVirtualArena),
        arena : CanonicalAstArena,
      )
        arenas.append(arena)
      end
    CRYSTAL

    converter.__test_repair_receiver_bound_call_targets

    append = functions.find { |candidate| candidate.name.starts_with?("append_concrete_arena$") }
    append.should_not be_nil
    append_call = append.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("#append") }
    append_call.should_not be_nil
    append_call.not_nil!.method_name.should contain("$CanonicalAstArena")
    converter.module.has_function_with_body?(append_call.not_nil!.method_name).should be_true

    push_call = functions
      .select { |candidate| candidate.name.includes?("#append$CanonicalAstArena") }
      .flat_map(&.blocks)
      .flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("#push") }
    push_call.should_not be_nil
    converter.module.has_function_with_body?(push_call.not_nil!.method_name).should be_true
    converter.__test_receiver_repair_call_arg_matches_param?(
      "CanonicalAstArena",
      "CanonicalAstArena | CanonicalPageArena | CanonicalVirtualArena",
    ).should be_true
    converter.__test_receiver_repair_call_arg_matches_param?(
      "String",
      "CanonicalAstArena | CanonicalPageArena | CanonicalVirtualArena",
    ).should be_false
  end

  it "preserves only an exact typed callsite name across union-definition lookup" do
    converter, _ = parse_receiver_repair_source(<<-CRYSTAL)
      class CodecAstArena
      end

      class CodecPageArena
      end

      class CodecVirtualArena
      end

      alias CodecArenaLike = CodecAstArena | CodecPageArena | CodecVirtualArena

      class CodecArenaSink(T)
        def push(value : T)
          value
        end
      end

      CodecArenaSink(CodecArenaLike).new.push(CodecAstArena.new)
    CRYSTAL

    base_name = "CodecArenaSink(CodecAstArena | CodecPageArena | CodecVirtualArena)#push"
    concrete_name = "#{base_name}$CodecAstArena"
    union_name = "#{base_name}$CodecAstArena | CodecPageArena | CodecVirtualArena"

    converter.__test_method_name_codec_exact_callsite_name?(
      concrete_name,
      base_name,
      ["CodecAstArena"],
    ).should be_true
    converter.__test_method_name_codec_exact_callsite_name?(
      concrete_name,
      base_name,
      ["CodecAstArena | CodecPageArena | CodecVirtualArena"],
    ).should be_false
    converter.__test_method_name_codec_exact_callsite_name?(
      union_name,
      base_name,
      ["CodecAstArena | CodecPageArena | CodecVirtualArena"],
    ).should be_true
    converter.__test_method_name_codec_exact_callsite_name?(
      base_name,
      base_name,
      [] of String,
    ).should be_false
    converter.__test_method_name_codec_exact_callsite_name?(
      concrete_name,
      "#{base_name}$stale",
      ["CodecAstArena"],
    ).should be_false

    block_name = "#{base_name}$CodecAstArena_block"
    converter.__test_method_name_codec_exact_callsite_name?(
      block_name,
      base_name,
      ["CodecAstArena"],
      true,
    ).should be_true
    converter.__test_method_name_codec_exact_callsite_name?(
      block_name,
      base_name,
      ["CodecAstArena"],
    ).should be_false
    converter.__test_method_name_codec_exact_callsite_name?(
      "#{base_name}$CodecAstArena_splat",
      base_name,
      ["CodecAstArena"],
    ).should be_false
  end

  it "rekeys a child-class suffix to a canonical parent-class parameter" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class CanonicalRepairValue
      end

      class CanonicalRepairParameter < CanonicalRepairValue
      end

      class CanonicalRepairSink
        def store(value : CanonicalRepairValue) : CanonicalRepairValue
          value
        end
      end

      def store_repair_parameter(
        sink : CanonicalRepairSink,
        value : CanonicalRepairParameter,
      ) : CanonicalRepairValue
        sink.store(value)
      end
    CRYSTAL

    caller = functions.find do |candidate|
      candidate.name.starts_with?("store_repair_parameter$")
    end
    caller.should_not be_nil
    call = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.starts_with?("CanonicalRepairSink#store") }
    call.should_not be_nil
    canonical_name = "CanonicalRepairSink#store$CanonicalRepairValue"
    call.not_nil!.method_name.should eq(canonical_name)
    converter.module.has_function_with_body?(canonical_name).should be_true

    stale_name = "CanonicalRepairSink#store$CanonicalRepairParameter"
    call.not_nil!.method_name = stale_name
    rekeyed = converter.__test_rekey_receiver_repair_request_to_canonical_body(
      stale_name,
      "CanonicalRepairSink#store",
      "CanonicalRepairSink",
      ["CanonicalRepairParameter"],
      caller.not_nil!.name,
    )

    rekeyed.should be_true
    call.not_nil!.method_name.should eq(canonical_name)
    converter.__test_receiver_repair_call_arg_matches_param?(
      "CanonicalRepairParameter",
      "CanonicalRepairValue",
    ).should be_true
    converter.__test_receiver_repair_call_arg_matches_param?(
      "CanonicalRepairValue",
      "CanonicalRepairParameter",
    ).should be_false
  end

  it "rekeys a named child-class suffix to a nullable parent parameter" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      abstract class NullableRepairValue
      end

      class NullableRepairParameter < NullableRepairValue
      end

      class NullableRepairUnrelated
      end

      class NullableRepairSibling
      end

      class NullableRepairSink
        def store(
          value : NullableRepairValue?,
          *,
          enabled : Bool? = nil,
        ) : String
          enabled.nil? ? "nil" : "ok"
        end

        def pass(value : NullableRepairParameter) : String
          store(value, enabled: false)
        end
      end
    CRYSTAL

    caller = functions.find do |candidate|
      candidate.name.starts_with?("NullableRepairSink#pass$")
    end
    caller.should_not be_nil
    call = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.starts_with?("NullableRepairSink#store") }
    call.should_not be_nil
    stale_name = "NullableRepairSink#store$NullableRepairParameter_Bool"
    call.not_nil!.method_name.should eq(stale_name)
    canonical = functions.find do |candidate|
      candidate.name.starts_with?("NullableRepairSink#store$") &&
        candidate.name.includes?("Nil | NullableRepairValue") &&
        candidate.blocks.any? { |block| !block.instructions.empty? }
    end
    canonical.should_not be_nil
    canonical_name = canonical.not_nil!.name
    converter.module.has_function_with_body?(canonical_name).should be_true

    rekeyed = converter.__test_rekey_receiver_repair_request_to_canonical_body(
      stale_name,
      "NullableRepairSink#store",
      "NullableRepairSink",
      ["NullableRepairParameter", "Bool"],
      caller.not_nil!.name,
    )

    rekeyed.should be_true
    call.not_nil!.method_name.should eq(canonical_name)
    converter.__test_receiver_repair_call_arg_matches_param?(
      "NullableRepairParameter",
      "NullableRepairValue?",
    ).should be_true
    converter.__test_receiver_repair_call_arg_matches_param?(
      "NullableRepairUnrelated",
      "NullableRepairValue?",
    ).should be_false
    converter.__test_receiver_repair_call_arg_matches_param?(
      "NullableRepairValue",
      "NullableRepairParameter?",
    ).should be_false
    converter.__test_receiver_repair_call_arg_matches_param?(
      "NullableRepairParameter",
      "NullableRepairValue | NullableRepairSibling",
    ).should be_false
  end

  it "rekeys a named union of child classes to a nullable parent parameter" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      abstract class NullableUnionRepairValue
      end

      class NullableUnionRepairChild < NullableUnionRepairValue
      end

      class NullableUnionRepairSibling < NullableUnionRepairValue
      end

      class NullableUnionRepairUnrelated
      end

      class NullableUnionRepairSink
        def store(
          value : NullableUnionRepairValue?,
          *,
          enabled : Bool? = nil,
        ) : String
          enabled.nil? ? "nil" : "ok"
        end

        def pass(
          value : NullableUnionRepairChild | NullableUnionRepairValue | NullableUnionRepairSibling,
        ) : String
          store(value, enabled: false)
        end

        def reject(
          value : NullableUnionRepairChild | NullableUnionRepairUnrelated,
        ) : Nil
          nil
        end
      end
    CRYSTAL

    caller = functions.find do |candidate|
      candidate.name.starts_with?("NullableUnionRepairSink#pass$")
    end
    caller.should_not be_nil
    call = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.starts_with?("NullableUnionRepairSink#store") }
    call.should_not be_nil
    stale_name = call.not_nil!.method_name
    canonical = functions.find do |candidate|
      candidate.name.starts_with?("NullableUnionRepairSink#store$") &&
        candidate.name.includes?("Nil | NullableUnionRepairValue") &&
        candidate.blocks.any? { |block| !block.instructions.empty? }
    end
    canonical.should_not be_nil
    canonical_name = canonical.not_nil!.name
    converter.module.has_function_with_body?(canonical_name).should be_true

    value_param = caller.not_nil!.params.find { |param| param.name == "value" }
    value_param.should_not be_nil
    arg_type_name = converter.module.get_type_descriptor(value_param.not_nil!.type)
      .not_nil!.name
    arg_type_name.should contain("NullableUnionRepairChild")
    arg_type_name.should contain("NullableUnionRepairValue")
    arg_type_name.should contain("NullableUnionRepairSibling")

    rekeyed = converter.__test_rekey_receiver_repair_request_to_canonical_body(
      stale_name,
      "NullableUnionRepairSink#store",
      "NullableUnionRepairSink",
      [arg_type_name, "Bool"],
      caller.not_nil!.name,
    )

    rekeyed.should be_true
    call.not_nil!.method_name.should eq(canonical_name)
    converter.__test_receiver_repair_call_arg_matches_param?(
      arg_type_name,
      "NullableUnionRepairValue?",
    ).should be_true
    converter.__test_receiver_repair_call_arg_matches_param?(
      "NullableUnionRepairChild | NullableUnionRepairUnrelated",
      "NullableUnionRepairValue?",
    ).should be_false
  end

  it "preserves named-only call shape while rekeying a narrowed nullable parameter" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class NamedOnlyRepairSink
        def seed(
          condition : UInt32,
          self_type_name : String?,
          *,
          truthy : Bool,
        ) : Nil
          nil
        end

        def infer(
          condition : UInt32,
          self_type_name : String,
          truthy : Bool,
        ) : Nil
          seed(condition, self_type_name, truthy: truthy)
        end
      end
    CRYSTAL

    caller = functions.find do |candidate|
      candidate.name.starts_with?("NamedOnlyRepairSink#infer$")
    end
    caller.should_not be_nil
    call = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.starts_with?("NamedOnlyRepairSink#seed") }
    call.should_not be_nil
    stale_name = call.not_nil!.method_name
    stale_name.should eq("NamedOnlyRepairSink#seed$UInt32_String_Bool")
    canonical = functions.find do |candidate|
      candidate.name.starts_with?("NamedOnlyRepairSink#seed$") &&
        candidate.name.includes?("Nil | String") &&
        candidate.blocks.any? { |block| !block.instructions.empty? }
    end
    canonical.should_not be_nil
    canonical_name = canonical.not_nil!.name
    converter.module.has_function_with_body?(canonical_name).should be_true
    sibling = Adamas::HIR::Call.with_receiver_virtual(
      caller.not_nil!.next_value_id,
      call.not_nil!.type,
      call.not_nil!.receiver_value,
      stale_name,
      call.not_nil!.args,
      call.not_nil!.virtual,
    )
    call_block = caller.not_nil!.blocks.find do |block|
      block.instructions.includes?(call.not_nil!)
    end
    call_block.should_not be_nil
    call_index = call_block.not_nil!.instructions.index(call.not_nil!).not_nil!
    call_block.not_nil!.instructions.insert(call_index + 1, sibling)
    converter.__test_has_named_call_shape(
      caller.not_nil!.name,
      call.not_nil!.id,
    ).should be_true
    rekeyed = converter.__test_rekey_receiver_repair_request_to_canonical_body(
      stale_name,
      "NamedOnlyRepairSink#seed",
      "NamedOnlyRepairSink",
      ["UInt32", "String", "Bool"],
      caller.not_nil!.name,
    )
    rekeyed.should be_true

    repaired_call = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.id == call.not_nil!.id }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.method_name.should eq(canonical_name)
    sibling.method_name.should eq(stale_name)
    converter.__test_remove_hir_function(caller.not_nil!.name).should be_true
    converter.__test_has_named_call_shape(
      caller.not_nil!.name,
      call.not_nil!.id,
    ).should be_false
  end

  it "repairs stale self calls inside a class method without dropping real args" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      module Probe
        def self.enabled?(key : String) : Bool
          false
        end

        def self.trace(key : String) : Bool
          enabled?(key)
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.includes?("Probe.trace") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    call.should_not be_nil
    replace_with_stale_type_literal_receiver(
      converter,
      function.not_nil!,
      call.not_nil!,
      "Probe",
      "Probe#enabled?$String",
      false,
    )

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_false
    repaired_call.not_nil!.args.size.should eq(1)
    repaired_call.not_nil!.method_name.should start_with("Probe.enabled?")
  end

  it "does not drop an explicit same-type instance argument in a class method" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class Probe
        def self.enabled?(key : String) : Bool
          false
        end

        def enabled?(key : String) : Bool
          false
        end

        def self.trace(probe : Probe, key : String) : Bool
          probe.enabled?(key)
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.includes?("Probe.trace") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    call.should_not be_nil
    call.not_nil!.method_name = "Probe#enabled?$String"

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_true
    repaired_call.not_nil!.args.size.should eq(1)
  end

  it "repairs namespaced module class-self calls on the exact dot target" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      module Adamas
        module LayoutProbe
          def self.enabled?(key : String) : Bool
            false
          end

          def self.trace(key : String) : Bool
            enabled?(key)
          end
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.includes?("Adamas::LayoutProbe.trace") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    call.should_not be_nil
    replace_with_stale_type_literal_receiver(
      converter,
      function.not_nil!,
      call.not_nil!,
      "Adamas::LayoutProbe",
      "Adamas::LayoutProbe#enabled?$String",
      false,
    )

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_false
    repaired_call.not_nil!.args.size.should eq(1)
    repaired_call.not_nil!.method_name.should start_with("Adamas::LayoutProbe.enabled?")
  end

  it "repairs a namespaced zero-argument class-self call without a suffix" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      module Adamas
        module LayoutProbe
          def self.enabled? : Bool
            false
          end

          def self.trace : Bool
            enabled?
          end
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.includes?("Adamas::LayoutProbe.trace") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    call.should_not be_nil
    original = call.not_nil!
    replace_with_stale_type_literal_receiver(
      converter,
      function.not_nil!,
      original,
      "Adamas::LayoutProbe",
      "Adamas::LayoutProbe#enabled?",
      true,
    )

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_false
    repaired_call.not_nil!.method_name.should eq("Adamas::LayoutProbe.enabled?")
  end

  it "keeps a same-name class-method block forward on the class separator" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class GlobForwarder
        def self.glob(values : Array(String), match : Int32 = 0, follow_symlinks : Bool = false) : Array(String)
          result = [] of String
          glob(values, match: match, follow_symlinks: follow_symlinks) { |value| result << value }
          result
        end

        def self.glob(values : Array(String), match : Int32 = 0, follow_symlinks : Bool = false, &block : String ->) : Nil
          nil
        end
      end
    CRYSTAL

    function = functions.find do |candidate|
      candidate.name.starts_with?("GlobForwarder.glob$") && !candidate.name.includes?("_block")
    end
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("glob") && instruction.has_block? }
    call.should_not be_nil
    original = call.not_nil!
    block = function.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(original)
    end
    block.should_not be_nil
    call_index = block.not_nil!.instructions.index(original).not_nil!
    block.not_nil!.instructions[call_index] = Adamas::HIR::Call.without_receiver_block(
      original.id,
      original.type,
      "GlobForwarder.glob",
      original.args,
      original.block_value,
      false
    )

    converter.__test_repair_receiver_bound_call_targets
    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("glob") && instruction.has_block? }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_false
    repaired_call.not_nil!.method_name.should contain("GlobForwarder.glob")
    repaired_call.not_nil!.method_name.should contain("_block")
  end

  it "does not guess an enum identity from its raw integer carrier" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      enum RepairStrategy
        Stack
        GC
      end

      class RepairResult
        def add(id : UInt32, strategy : RepairStrategy)
        end
      end

      class RepairAssigner
        def assign(result : RepairResult, strategy : RepairStrategy)
          result.add(1_u32, strategy)
        end
      end
    CRYSTAL

    assign = functions.find { |candidate| candidate.name.starts_with?("RepairAssigner#assign$") }
    assign.should_not be_nil
    add_call = assign.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.starts_with?("RepairResult#add") }
    add_call.should_not be_nil
    call = add_call.not_nil!
    call.method_name.should eq("RepairResult#add$UInt32_RepairStrategy")

    strategy_id = call.args[1]
    producer_block = assign.not_nil!.blocks.find do |block|
      block.instructions.any? { |instruction| instruction.id == strategy_id }
    end
    producer_block.should_not be_nil
    producer_index = producer_block.not_nil!.instructions.index do |instruction|
      instruction.id == strategy_id
    end
    producer_index.should_not be_nil
    producer_block.not_nil!.instructions[producer_index.not_nil!] =
      Adamas::HIR::Literal.new(strategy_id, Adamas::HIR::TypeRef::INT32, 0_i64)
    call.method_name = "RepairResult#add$UInt32_Int32"
    rekeyed = converter.__test_rekey_receiver_repair_request_to_canonical_body(
      "RepairResult#add$UInt32_Int32",
      "RepairResult#add",
      "RepairResult",
      ["UInt32", "Int32"],
      assign.not_nil!.name,
    )

    rekeyed.should be_false
    call.method_name.should eq("RepairResult#add$UInt32_Int32")
  end

  it "uses retained function-local enum provenance to repair a carrier-typed call" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      enum RetainedRepairStrategy
        Stack
        GC
      end

      class RetainedRepairResult
        def add(id : UInt32, strategy : RetainedRepairStrategy)
        end
      end

      class RetainedRepairAssigner
        def assign(result : RetainedRepairResult, strategy : RetainedRepairStrategy)
          result.add(1_u32, strategy)
        end
      end
    CRYSTAL

    assign = functions.find do |candidate|
      candidate.name.starts_with?("RetainedRepairAssigner#assign$")
    end
    assign.should_not be_nil
    add_call = assign.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.starts_with?("RetainedRepairResult#add") }
    add_call.should_not be_nil
    call = add_call.not_nil!
    call.method_name.should eq(
      "RetainedRepairResult#add$UInt32_RetainedRepairStrategy",
    )

    strategy_id = call.args[1]
    converter.__test_retained_function_enum_name(
      assign.not_nil!.name,
      strategy_id,
    ).should eq("RetainedRepairStrategy")
    producer_block = assign.not_nil!.blocks.find do |block|
      block.instructions.any? { |instruction| instruction.id == strategy_id }
    end
    producer_block.should_not be_nil
    producer_index = producer_block.not_nil!.instructions.index do |instruction|
      instruction.id == strategy_id
    end
    producer_index.should_not be_nil
    producer_block.not_nil!.instructions[producer_index.not_nil!] =
      Adamas::HIR::Literal.new(strategy_id, Adamas::HIR::TypeRef::INT32, 0_i64)
    call_block = assign.not_nil!.blocks.find do |block|
      block.instructions.includes?(call)
    end
    call_block.should_not be_nil
    call_index = call_block.not_nil!.instructions.index(call)
    call_index.should_not be_nil
    call_block.not_nil!.instructions[call_index.not_nil!] =
      Adamas::HIR::Call.with_receiver(
        call.id,
        call.type,
        call.receiver_value,
        "RetainedRepairResult#add$UInt32_Int32",
        call.args,
      )

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = assign.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.starts_with?("RetainedRepairResult#add") }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.method_name.should eq(
      "RetainedRepairResult#add$UInt32_RetainedRepairStrategy",
    )
  end

  it "retains a typed empty-array identity for late receiver repair" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class EmptyArrayRepairSink
        def consume(values : Array(UInt32)) : Nil
          nil
        end
      end

      def consume_empty_array_for_repair(sink : EmptyArrayRepairSink) : Nil
        sink.consume([] of UInt32)
      end
    CRYSTAL

    caller = functions.find do |candidate|
      candidate.name.starts_with?("consume_empty_array_for_repair$")
    end
    caller.should_not be_nil
    call = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.starts_with?("EmptyArrayRepairSink#consume") }
    call.should_not be_nil
    call.not_nil!.args.size.should eq(1)
    converter.__test_collected_function_value_type_name(
      caller.not_nil!.name,
      call.not_nil!.args[0],
    ).should eq("Array(UInt32)")
  end

  it "preserves annotated union ABI types only for shared arity symbols" do
    converter, _ = parse_receiver_repair_source(<<-CRYSTAL)
      class SharedArityRepairScope
      end
    CRYSTAL

    union_name = "Nil | SharedArityRepairScope"
    converter.__test_preserves_annotated_union_param_for_shared_arity?(
      "SharedArityRepairSink#expand$UInt32_Hash(String, UInt32)$arity4",
      "SharedArityRepairScope?",
      union_name,
    ).should be_true
    converter.__test_preserves_annotated_union_param_for_shared_arity?(
      "SharedArityRepairSink#expand$UInt32_Hash(String, UInt32)_Nil",
      "SharedArityRepairScope?",
      union_name,
    ).should be_false
    converter.__test_preserves_annotated_union_param_for_shared_arity?(
      "SharedArityRepairSink#expand$UInt32$arity4",
      nil,
      union_name,
    ).should be_false
  end

  it "rejects inferred unions that replace rather than narrow variants" do
    converter, _ = parse_receiver_repair_source(<<-CRYSTAL)
      class UnionPreferenceRepairScope
      end
    CRYSTAL

    converter.__test_prefers_inferred_union_type?(
      "Nil | UnionPreferenceRepairScope | String",
      "Nil | Array(UnionPreferenceRepairScope | String)",
    ).should be_false
    converter.__test_prefers_inferred_union_type?(
      "Nil | UnionPreferenceRepairScope | String",
      "Nil | UnionPreferenceRepairScope",
    ).should be_true
  end

  it "reuses a declared nullable body for exact non-generic calls" do
    _, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class NullableRecursiveIdentity
        def outer(value : String?) : Nil
          inner(value)
        end

        def inner(value : String?) : Nil
          if value
            outer(value)
          end
        end

        def run(value : String) : Nil
          outer(value)
        end
      end
    CRYSTAL

    materialized = {} of String => Array(String)
    ["outer", "inner"].each do |method_name|
      materialized[method_name] = functions.select do |function|
        function.name.starts_with?("NullableRecursiveIdentity##{method_name}$") &&
          function.blocks.any? { |block| !block.instructions.empty? }
      end.map(&.name).sort
    end

    materialized.should eq({
      "outer" => ["NullableRecursiveIdentity#outer$Nil | String"],
      "inner" => ["NullableRecursiveIdentity#inner$Nil | String"],
    })
  end

  it "keeps union dispatch for distinct explicit overloads" do
    _, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class ExplicitNullableDispatch
        def choose(value : Nil) : Int32
          1
        end

        def choose(value : String) : Int32
          2
        end

        def run(value : String?) : Int32
          choose(value)
        end
      end
    CRYSTAL

    run = functions.find do |function|
      function.name == "ExplicitNullableDispatch#run$Nil | String"
    end
    run.should_not be_nil

    instructions = run.not_nil!.blocks.flat_map(&.instructions)
    instructions.count { |instruction| instruction.is_a?(Adamas::HIR::UnionIs) }.should eq(1)
    targets = instructions.compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name)
    end.select { |name| name.starts_with?("ExplicitNullableDispatch#choose$") }.sort
    targets.should eq([
      "ExplicitNullableDispatch#choose$Nil",
      "ExplicitNullableDispatch#choose$String",
    ])
  end

  it "keeps lazy union dispatch for distinct defaulted overloads" do
    _, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class DefaultedNullableDispatch
        def choose(value : Nil, bonus : Int32 = 1) : Int32
          10 + bonus
        end

        def choose(value : String, bonus : Int32 = 2) : Int32
          20 + bonus
        end

        def run(value : String?) : Int32
          choose(value)
        end
      end
    CRYSTAL

    run = functions.find do |function|
      function.name == "DefaultedNullableDispatch#run$Nil | String"
    end
    run.should_not be_nil

    instructions = run.not_nil!.blocks.flat_map(&.instructions)
    instructions.count { |instruction| instruction.is_a?(Adamas::HIR::UnionIs) }.should eq(1)
    targets = instructions.compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name)
    end.select { |name| name.starts_with?("DefaultedNullableDispatch#choose$") }.sort
    targets.should eq([
      "DefaultedNullableDispatch#choose$Nil",
      "DefaultedNullableDispatch#choose$String",
    ])
  end

  it "keeps the selected defaulted overload while forcing a body-inferred union return" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class ForceIdentityDefaultedOverload
        def choose(value : Bool, bonus : Int32 = 1)
          value ? bonus : "no"
        end

        def choose(value : String, bonus : Int32 = 2)
          value.empty? ? bonus : value
        end

        def run(value : Bool)
          choose(value)
        end
      end
    CRYSTAL

    run = functions.find do |function|
      function.name == "ForceIdentityDefaultedOverload#run$Bool"
    end
    run.should_not be_nil

    call = run.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.starts_with?("ForceIdentityDefaultedOverload#choose$") }
    call.should_not be_nil
    call.not_nil!.method_name.should eq("ForceIdentityDefaultedOverload#choose$Bool_Int32")

    selected = functions.find do |function|
      function.name == "ForceIdentityDefaultedOverload#choose$Bool_Int32"
    end
    selected.should_not be_nil
    run.not_nil!.return_type.should eq(selected.not_nil!.return_type)
    converter.__test_type_name(run.not_nil!.return_type)
      .split('|')
      .map(&.strip)
      .sort
      .should eq(["Int32", "String"])
    converter.__test_force_lower_function_for_return_type(
      "ForceIdentityDefaultedOverload#choose"
    ).should be_false

    selected_name = "ForceIdentityDefaultedOverload#choose$Bool_Int32"
    converter.__test_remove_hir_function(selected_name).should be_true
    converter.__test_reset_function_lowering_state("ForceIdentityDefaultedOverload#choose")
    converter.__test_reset_function_lowering_state(selected_name)
    converter.__test_force_lower_function_for_return_type(
      "ForceIdentityDefaultedOverload#choose"
    ).should be_false
    converter.module.has_function_with_body?(selected_name).should be_false

    converter.__test_reset_function_lowering_state(selected_name)
    converter.__test_force_lower_function_for_return_type(selected_name).should be_true
    converter.module.has_function_with_body?(selected_name).should be_true
  end

  it "keeps union dispatch for distinct named-only overloads" do
    _, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class NamedNullableDispatch
        def choose(value : Nil, *, bonus : Int32 = 1) : Int32
          10 + bonus
        end

        def choose(value : String, *, bonus : Int32 = 2) : Int32
          20 + bonus
        end

        def run(value : String?) : Int32
          choose(value, bonus: 7)
        end
      end
    CRYSTAL

    run = functions.find do |function|
      function.name == "NamedNullableDispatch#run$Nil | String"
    end
    run.should_not be_nil

    instructions = run.not_nil!.blocks.flat_map(&.instructions)
    instructions.count { |instruction| instruction.is_a?(Adamas::HIR::UnionIs) }.should eq(1)
    targets = instructions.compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name)
    end.select { |name| name.starts_with?("NamedNullableDispatch#choose$") }.sort
    targets.should eq([
      "NamedNullableDispatch#choose$Nil_Int32",
      "NamedNullableDispatch#choose$String_Int32",
    ])
  end

  it "keeps union dispatch for distinct splat overloads" do
    _, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class SplatNullableDispatch
        def choose(value : Nil, *bonus : Int32) : Int32
          10 + bonus[0]
        end

        def choose(value : String, *bonus : Int32) : Int32
          20 + bonus[0]
        end

        def run(value : String?) : Int32
          choose(value, *{7})
        end
      end
    CRYSTAL

    run = functions.find do |function|
      function.name == "SplatNullableDispatch#run$Nil | String"
    end
    run.should_not be_nil

    instructions = run.not_nil!.blocks.flat_map(&.instructions)
    instructions.count { |instruction| instruction.is_a?(Adamas::HIR::UnionIs) }.should eq(1)
    target_calls = instructions.compact_map(&.as?(Adamas::HIR::Call)).select do |call|
      call.method_name.starts_with?("SplatNullableDispatch#choose$")
    end
    targets = target_calls.map(&.method_name).sort
    targets.size.should eq(2)
    targets.any? { |name| name.starts_with?("SplatNullableDispatch#choose$Nil_") }.should be_true
    targets.any? { |name| name.starts_with?("SplatNullableDispatch#choose$String_") }.should be_true
    targets.none? { |name| name.includes?("Nil | String") }.should be_true
    tuple_allocations = instructions.compact_map(&.as?(Adamas::HIR::Allocate)).map(&.id)
    target_calls.all? { |call| tuple_allocations.includes?(call.args.last) }.should be_true
  end

  it "does not repack an empty tuple at a union-dispatched splat slot" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class EmptySplatNullableDispatch
        def choose(value : Nil, *bonus : Int32) : Int32
          10 + bonus.size
        end

        def choose(value : String, *bonus : Int32) : Int32
          20 + bonus.size
        end

        def run(value : String?) : Int32
          choose(value, *Tuple.new)
        end

        def probe : Int32
          run(nil)
        end
      end
    CRYSTAL

    run = functions.find do |function|
      function.name == "EmptySplatNullableDispatch#run$Nil | String"
    end
    run.should_not be_nil

    instructions = run.not_nil!.blocks.flat_map(&.instructions)
    target_calls = instructions.compact_map(&.as?(Adamas::HIR::Call)).select do |call|
      call.method_name.starts_with?("EmptySplatNullableDispatch#choose$")
    end
    target_calls.size.should eq(2)
    splat_types = target_calls.map do |call|
      splat_arg = instructions.find { |instruction| instruction.id == call.args.last }
      splat_arg.should_not be_nil
      converter.__test_type_name(splat_arg.not_nil!.type)
    end
    splat_types.should eq(["Tuple()", "Tuple()"])

    exact_run = converter.module.functions.find do |function|
      function.name == "EmptySplatNullableDispatch#run$Nil"
    end
    exact_run.should_not be_nil
    repaired_call = exact_run.not_nil!.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name.starts_with?("EmptySplatNullableDispatch#choose$") }
    repaired_call.should_not be_nil
    canonical_target = repaired_call.not_nil!.method_name.rchop("_splat")
    converter.__test_lower_function_if_needed(canonical_target)
    converter.module.has_function_with_body?(canonical_target).should be_true
    converter.__test_rekey_receiver_repair_request_to_canonical_body(
      repaired_call.not_nil!.method_name,
      "EmptySplatNullableDispatch#choose",
      "EmptySplatNullableDispatch",
      ["Nil", "Tuple()"],
      exact_run.not_nil!.name,
      has_splat: true,
    ).should be_true
    repaired_call.not_nil!.method_name.should eq(
      "EmptySplatNullableDispatch#choose$Nil_Tuple()",
    )
    converter.module.has_function_with_body?(repaired_call.not_nil!.method_name).should be_true
  end
end
