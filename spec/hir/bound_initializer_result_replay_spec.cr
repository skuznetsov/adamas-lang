require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def spec_replay_bound_initializer_at_depth(depth : Int32, bypass_inline_yield : Bool) : Nil
    name = mangle_function_name("BoundInitializerCaller.allocate", [TypeRef::INT32])
    remember_callsite_arg_types(name, [TypeRef::INT32])
    @force_lower_return_type_depth = depth
    @force_lower_yield_free_only_depth = bypass_inline_yield ? 1 : 0
    @force_lower_retry_driver_active = true
    begin
      force_lower_function_for_return_type(name, bypass_inline_yield: bypass_inline_yield)
    ensure
      @force_lower_retry_driver_active = false
      @force_lower_return_type_depth = 0
      @force_lower_yield_free_only_depth = 0
    end

    request = @force_lower_retry_work.find do |work|
      work.is_a?(ForceLowerSuspendedRequest) && work.name == name
    end.as?(ForceLowerSuspendedRequest)
    request.should_not be_nil, "the allocator caller must wait for its bound initializer"
    request = request.not_nil!
    pending = request.pending
    pending.producer.should start_with("BoundInitializer#initialize")
    pending.producer.should contain("_bound")
    pending.producer_requires_result.should be_false
    force_lower_replay_callsite_current?(pending.producer, pending.producer_replay.not_nil!).should be_true
    @module.has_function_with_body?(pending.producer).should be_false

    run_force_lower_retry_driver(request).should be_true
    flush_pending_functions
    refresh_void_type_params
    flush_deferred_allocators
    settled_force_lower_result?(name).should be_true
    settled_force_lower_result?(pending.producer).should be_true
    initializer = @module.function_by_name(pending.producer).not_nil!
    initializer.params.map(&.type).should eq([@class_info["BoundInitializer"].type_ref, TypeRef::INT32])
    initializer.return_type.should eq(TypeRef::INT32)
    @materialized_initializer_sources[pending.producer].source_def.same?(pending.producer_source.source_def).should be_true
    @materialized_initializer_sources[pending.producer].source_arena.same?(pending.producer_source.source_arena).should be_true
    call = initializer.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Call) && instruction.method_name == "BoundInitializerFork.value"
    end.as?(Call).not_nil!
    callee = @module.function_by_name(call.method_name).not_nil!
    call.type.should eq(callee.return_type)
    source_block_result_union_members(callee.return_type).not_nil!.to_set.should eq(Set{TypeRef::NIL, TypeRef::INT32})
  end
end

private def lower_bound_initializer_replay_fixture(depth : Int32, bypass_inline_yield : Bool) : Nil
  source = <<-CRYSTAL
    lib BoundInitializerC
      fun getchar : Int32
    end

    struct BoundInitializerFork
      def self.value
        code = BoundInitializerC.getchar
        code < 0 ? nil : code
      end
    end

    class BoundInitializer
      @value : Int32

      def initialize(*, fallback : Int32)
        result = BoundInitializerFork.value
        @value = result || fallback
      end
    end

    struct BoundInitializerCaller
      def self.allocate(fallback : Int32)
        BoundInitializer.new(fallback: fallback)
      end
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::LibNode
      converter.register_lib(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  converter.spec_replay_bound_initializer_at_depth(depth, bypass_inline_yield)
end

describe "source result demand through a bound allocator initializer" do
  it "replays the selected initializer after the body demand hits the depth cap" do
    lower_bound_initializer_replay_fixture(1, true)
  end

  it "waits for the exact initializer already queued behind its own producer" do
    lower_bound_initializer_replay_fixture(2, false)
  end
end
