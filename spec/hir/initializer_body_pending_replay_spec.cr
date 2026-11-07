require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def spec_finish_pending_source_work : Nil
    @force_lower_return_type_depth = 0
    flush_pending_functions
    refresh_void_type_params
    flush_deferred_allocators
  end

  def spec_initializer_source_matches?(
    name : String,
    definition : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Bool
    source = @materialized_initializer_sources[name]?
    !!(source && source.function.name == name && source.source_def.same?(definition) &&
      arena_map_key(source.source_arena) == arena_map_key(arena) &&
      initializer_source_definition_current?(source))
  end

  def spec_initializer_source_rejects_stale_definition?(name : String, replacement : Adamas::Compiler::Frontend::DefNode) : Bool
    source = @materialized_initializer_sources[name]?
    return false unless source
    original = @function_defs[source.source_name]?
    return false unless original
    @function_defs[source.source_name] = replacement
    begin
      !initializer_source_definition_current?(source)
    ensure
      @function_defs[source.source_name] = original
    end
  end

  def spec_initializer_source_rejects_stale_arena?(name : String, replacement : Adamas::Compiler::Frontend::ArenaLike) : Bool
    source = @materialized_initializer_sources[name]?
    return false unless source
    original = @function_def_arenas[source.source_name]?
    return false unless original
    @function_def_arenas[source.source_name] = replacement
    begin
      !initializer_source_definition_current?(source)
    ensure
      @function_def_arenas[source.source_name] = original
    end
  end

  def spec_replay_state_is_settled? : Bool
    @force_lower_provisional_dependencies.empty? &&
      @force_lower_result_suspensions.empty? &&
      @force_lower_return_type_depth == 0
  end

  def spec_force_lower_return_type_depth : Int32
    @force_lower_return_type_depth
  end

  def spec_registered_source_names(definition : Adamas::Compiler::Frontend::DefNode) : Array(String)
    names = [] of String
    @function_defs.each do |name, candidate|
      names << name if candidate.same?(definition)
    end
    names.sort
  end

  def spec_force_exact_consumer_at_depth(name : String, depth : Int32) : {Bool, Bool}
    remember_callsite_arg_types(name, [] of TypeRef)
    callsite = @pending_arg_types[name]?
    empty_call_shape = if callsite
                         callsite.types.empty? && !callsite.has_block && !callsite.has_named_args &&
                           callsite.named_arg_names.nil? && callsite.source_argument_facts.nil? &&
                           callsite.source_binding.nil?
                       else
                         false
                       end
    saved_depth = @force_lower_return_type_depth
    @force_lower_return_type_depth = depth
    begin
      {force_lower_function_for_return_type(name), empty_call_shape}
    ensure
      @force_lower_return_type_depth = saved_depth
    end
  end

  @spec_initializer_pending_events = [] of Tuple(String, String, Bool, UInt64, UInt64, String, Bool, Int32)

  def spec_initializer_pending_events : Array(Tuple(String, String, Bool, UInt64, UInt64, String, Bool, Int32))
    @spec_initializer_pending_events
  end

  private def retry_suspended_exact_result(
    pending : ExactResultPending,
    replay : ForceLowerReplayCallsite,
    refused_mark : Int32,
    bypass_inline_yield : Bool,
  ) : Bool
    @spec_initializer_pending_events << {
      pending.consumer,
      pending.producer,
      pending.producer_requires_result,
      pending.producer_source.source_def.object_id.to_u64,
      arena_map_key(pending.producer_source.source_arena),
      pending.producer_source.source_registry_name || "",
      @force_lower_depth_refused.includes?(pending.producer),
      @force_lower_return_type_depth,
    }
    previous_def
  end
end

private def lower_initializer_body_pending_fixture : {Adamas::HIR::AstToHir, Adamas::Compiler::Frontend::ArenaLike, Adamas::Compiler::Frontend::DefNode, Adamas::Compiler::Frontend::DefNode, Adamas::Compiler::Frontend::DefNode}
  source = <<-CRYSTAL
    # The spec drives BodyDemandConsumer.read through the real force-lowering
    # entry at a controlled budget. Its source body still owns the allocator,
    # initializer, and getter demand exercised by this contract.
    class BodyDemandTarget
      @value : Int32

      def initialize
        @value = 77
        nil
      end

      def value
        @value
      end
    end

    class StaleInitializerOwner
      def initialize
        nil
      end
    end

    class BodyDemandConsumer
      def self.read
        BodyDemandTarget.new.value
      end
    end
    CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena

  target_initializer = nil.as(Adamas::Compiler::Frontend::DefNode?)
  stale_initializer = nil.as(Adamas::Compiler::Frontend::DefNode?)
  consumer_source = nil.as(Adamas::Compiler::Frontend::DefNode?)
  target_owner = nil.as(Adamas::Compiler::Frontend::ClassNode?)
  stale_owner = nil.as(Adamas::Compiler::Frontend::ClassNode?)
  consumer_owner = nil.as(Adamas::Compiler::Frontend::ClassNode?)
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      case String.new(node.name)
      when "BodyDemandTarget"
        target_owner = node
      when "StaleInitializerOwner"
        stale_owner = node
      when "BodyDemandConsumer"
        consumer_owner = node
      end
    end
  end
  target_owner.should_not be_nil
  stale_owner.should_not be_nil

  target_owner.not_nil!.body.not_nil!.each do |member_id|
    if definition = arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
      target_initializer = definition if String.new(definition.name) == "initialize"
    end
  end
  stale_owner.not_nil!.body.not_nil!.each do |member_id|
    if definition = arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
      stale_initializer = definition if String.new(definition.name) == "initialize"
    end
  end
  consumer_owner.should_not be_nil
  consumer_owner.not_nil!.body.not_nil!.each do |member_id|
    if definition = arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
      consumer_source = definition if String.new(definition.name) == "read"
    end
  end
  target_initializer.should_not be_nil
  stale_initializer.should_not be_nil
  consumer_source.should_not be_nil

  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.arena = arena

  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    end
  end

  converter.spec_force_lower_return_type_depth.should eq(0)
  consumer_names = converter.spec_registered_source_names(consumer_source.not_nil!)
  consumer_names.size.should eq(1)
  consumer_name = consumer_names.first
  consumer_name.should start_with("BodyDemandConsumer")
  forced, empty_call_shape = converter.spec_force_exact_consumer_at_depth(consumer_name, 3)
  forced.should be_true
  empty_call_shape.should be_true
  converter.spec_force_lower_return_type_depth.should eq(0)
  converter.spec_finish_pending_source_work
  {converter, arena, target_initializer.not_nil!, stale_initializer.not_nil!, consumer_source.not_nil!}
end

describe "initializer body demand through generated allocation" do
  it "resumes the exact initializer body without borrowing the allocator result type" do
    converter, arena, initializer_source, stale_source, consumer_source = lower_initializer_body_pending_fixture
    target_type = converter.class_info["BodyDemandTarget"].type_ref
    target_layout = converter.class_info["BodyDemandTarget"].ivars.find { |ivar| ivar.name == "@value" }
    target_layout.should_not be_nil
    target_layout.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)

    consumer_name = converter.spec_registered_source_names(consumer_source).first
    consumer = converter.module.function_by_name(consumer_name).not_nil!
    consumer.name.should eq(consumer_name)
    consumer.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    allocation_owner = consumer
    allocation_owner.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    allocation_call = allocation_owner.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name.starts_with?("BodyDemandTarget.") && call.type == target_type }
    allocation_call.should_not be_nil
    allocator = converter.module.function_by_name(allocation_call.not_nil!.method_name)
    allocator.should_not be_nil

    initializer_call = allocator.not_nil!.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name.starts_with?("BodyDemandTarget#initialize") }
    initializer_call.should_not be_nil
    initializer_call.not_nil!.type.should eq(Adamas::HIR::TypeRef::NIL)

    initializer_name = initializer_call.not_nil!.method_name
    initializer = converter.module.function_by_name(initializer_name)
    initializer.should_not be_nil
    initializer.not_nil!.name.should eq(initializer_name)
    initializer.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::NIL)
    initializer.not_nil!.blocks.flat_map(&.instructions).any? do |instruction|
      instruction.is_a?(Adamas::HIR::FieldSet) && instruction.field_name.lstrip('@') == "value"
    end.should be_true
    initializer.not_nil!.blocks.flat_map(&.instructions).any? do |instruction|
      instruction.is_a?(Adamas::HIR::Literal) && instruction.value == 77_i64
    end.should be_true

    initializer_pending = converter.spec_initializer_pending_events.find do |event|
      event[1] == initializer_name
    end
    initializer_pending.should_not be_nil
    initializer_pending.not_nil![0].should eq(consumer_name)
    initializer_pending.not_nil![2].should be_false
    initializer_pending.not_nil![3].should eq(initializer_source.object_id.to_u64)
    initializer_pending.not_nil![4].should eq(arena.object_id.to_u64)
    initializer_pending.not_nil![5].should eq(initializer_name)
    initializer_pending.not_nil![6].should be_true
    initializer_pending.not_nil![7].should eq(3)

    converter.spec_initializer_source_matches?(initializer.not_nil!.name, initializer_source, arena).should be_true
    converter.spec_initializer_source_rejects_stale_definition?(initializer.not_nil!.name, stale_source).should be_true

    other_arena = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("1"),
    ).parse_program.arena
    converter.spec_initializer_source_rejects_stale_arena?(initializer.not_nil!.name, other_arena).should be_true
    converter.spec_initializer_source_matches?(initializer.not_nil!.name, initializer_source, arena).should be_true
    converter.spec_replay_state_is_settled?.should be_true
  end
end
