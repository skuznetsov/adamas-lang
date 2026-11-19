require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def spec_queued_static_source_result : Nil
    target = "QueuedStaticResult.read$Int32"
    producer = "QueuedStaticResult.value"
    source_def = @function_defs[producer]
    source_arena = @function_def_arenas[producer]
    source = ForceLowerExactSourceBinding.new(source_def, source_arena, producer)
    callsite = remember_callsite_arg_types(producer, [] of TypeRef).not_nil!
    replay = ForceLowerReplayCallsite.new(source_def, source_arena, callsite,
      @type_param_map.dup, @current_namespace_override, producer, exact_source_binding: source)

    # Model the state after the nested demand moved from the provisional map
    # to a current queue entry. The declared ABI alone does not certify the
    # call's source result.
    @force_lower_retry_work << ForceLowerRetryRequest.new(producer, [] of String, false, replay, source, true)
    @force_lower_provisional_dependencies.has_key?(producer).should be_false
    remember_callsite_arg_types(target, [TypeRef::INT32])

    @force_lower_retry_driver_active = true
    begin
      force_lower_function_for_return_type(target)
    ensure
      @force_lower_retry_driver_active = false
    end

    request = @force_lower_retry_work.find do |work|
      work.is_a?(ForceLowerSuspendedRequest) && work.name == target
    end.as?(ForceLowerSuspendedRequest)
    request.should_not be_nil
    pending = request.not_nil!.pending
    pending.producer.should eq(producer)
    pending.producer_replay.should_not be_nil
    @module.has_function_with_body?(target).should be_false

    @force_lower_retry_work.clear
    run_force_lower_retry_driver(request.not_nil!).should be_true
    settled_force_lower_result?(producer).should be_true
    settled_force_lower_result?(target).should be_true
    function = @module.function_by_name(target).not_nil!
    function.return_type.should eq(TypeRef::INT32)
    call = function.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Call) && instruction.method_name == producer
    end.as?(Call).not_nil!
    source_block_result_union_members(call.type).not_nil!.to_set.should eq(Set{TypeRef::NIL, TypeRef::INT32})
  end
end

describe "a bare static call with queued source result work" do
  it "waits for the exact queued body even when its declared ABI is known" do
    source = <<-CRYSTAL
      lib QueuedStaticInput
        fun getchar : Int32
      end

      struct QueuedStaticResult
        def self.read(fallback : Int32) : Int32
          value = self.value
          value || fallback
        end

        private def self.value : Int32?
          current = QueuedStaticInput.getchar
          current < 0 ? nil : current
        end
      end
      CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    compiler = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    compiler.no_prelude = true
    program.roots.each do |root|
      case node = arena[root]
      when Adamas::Compiler::Frontend::LibNode
        compiler.register_lib(node)
      when Adamas::Compiler::Frontend::ClassNode
        compiler.register_class(node)
      end
    end
    compiler.spec_queued_static_source_result
  end
end
