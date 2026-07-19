require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/symbol_table"
require "../../src/compiler/semantic/symbol"
require "../../src/compiler/semantic/collectors/symbol_collector"
require "../../src/compiler/semantic/resolvers/name_resolver"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"
require "../../src/compiler/hir/hir"
require "../../src/compiler/semantic/identity/hir_adapter"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"

include Adamas::Compiler
include Adamas::Compiler::Semantic

class Adamas::HIR::Call
  # T1b0 deliberately has no production attach API: current HIR has no typed
  # source owner with which to verify a semantic callsite. T1b1 must establish
  # that owner before production binding is exposed.
  def __test_bind_resolution_handoff(handoff : Adamas::Compiler::Semantic::CallResolutionHandoff) : self
    @resolution_handoff = handoff
    self
  end
end

class Adamas::MIR::HIRToMIRLowering
  def __test_lower_direct_handoff(call : Adamas::HIR::Call) : Adamas::MIR::Call?
    return_type = Adamas::MIR::TypeRef.from_hir(call.type)
    target = @mir_module.create_function(call.method_name, return_type)
    caller = @mir_module.create_function("__t1b0_handoff_caller", return_type)

    if call.has_receiver?
      target.add_param("self", Adamas::MIR::TypeRef::POINTER)
      caller_receiver = caller.add_param("self", Adamas::MIR::TypeRef::POINTER)
      @value_map[call.receiver_value] = caller_receiver
    end
    call.args.each_with_index do |arg, index|
      target.add_param("arg#{index}", Adamas::MIR::TypeRef::INT32)
      caller_arg = caller.add_param("arg#{index}", Adamas::MIR::TypeRef::INT32)
      @value_map[arg] = caller_arg
    end

    @builder = Adamas::MIR::Builder.new(caller)
    lower_call(call)
    caller.blocks.flat_map(&.instructions).find(&.is_a?(Adamas::MIR::Call)).try(&.as(Adamas::MIR::Call))
  end
end

class Adamas::MIR::CopyPropagationPass
  def __test_rewrite_call(
    call : Adamas::MIR::Call,
    replacements : Hash(Adamas::MIR::ValueId, Adamas::MIR::ValueId),
  ) : Adamas::MIR::Call
    rewritten = rewrite_instruction(
      call,
      replacements,
      0_u32,
      1,
      {2_u32 => 0_u32},
      {2_u32 => 0},
      nil,
      {0_u32 => 2},
    )
    rewritten.as(Adamas::MIR::Call)
  end
end

private def infer_handoff_source(source : String, capture_call_resolutions : Bool = true)
  lexer = Frontend::Lexer.new(source)
  parser = Frontend::Parser.new(lexer)
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = Semantic::TypeInferenceEngine.new(
    program,
    name_result.identifier_symbols,
    analyzer.global_context.symbol_table,
    capture_call_resolutions: capture_call_resolutions,
  )
  engine.infer_types
  {program, engine}
end

private def source_call_ids(program : Frontend::Program) : Array(Frontend::ExprId)
  ids = [] of Frontend::ExprId
  program.ast_arena.nodes.each_with_index do |node, index|
    ids << Frontend::ExprId.new(index) if node.is_a?(Frontend::CallNode)
  end
  ids
end

private def source_resolution_for(
  program : Frontend::Program,
  engine : Semantic::TypeInferenceEngine,
  expr_id : Frontend::ExprId,
) : CallResolution
  engine.resolution_for(
    CallsiteIdentity.new(program.ast_arena.object_id.to_u64, expr_id.index),
  ).not_nil!
end

private def source_resolutions(
  program : Frontend::Program,
  engine : Semantic::TypeInferenceEngine,
) : Array(CallResolution)
  source_call_ids(program).compact_map do |expr_id|
    engine.resolution_for(
      CallsiteIdentity.new(program.ast_arena.object_id.to_u64, expr_id.index),
    )
  end
end

describe "same-owner semantic call-resolution handoff" do
  it "keeps distinct source resolutions on one typed body key" do
    source = <<-CRYSTAL
      class SameTargetProbe
        def target(value : Int32) : Int32
          value
        end
      end

      probe = SameTargetProbe.new
      probe.target(1)
      probe.target(2)
    CRYSTAL

    program, engine = infer_handoff_source(source)
    resolutions = source_call_ids(program).map { |id| source_resolution_for(program, engine, id) }
    resolutions = resolutions.select { |resolution| resolution.arg_types.size == 1 }
    resolutions.size.should eq 2

    first = CallResolutionHandoff.from(resolutions[0]).not_nil!
    second = CallResolutionHandoff.from(resolutions[1]).not_nil!
    first.resolution_id.should_not eq second.resolution_id
    first.callsite.should eq resolutions[0].callsite
    second.callsite.should eq resolutions[1].callsite
    first.body_key.should eq second.body_key

    duplicate = CallResolutionHandoff.from(resolutions[0]).not_nil!
    Set{first, duplicate}.size.should eq 1
  end

  it "keeps equal display spellings distinct when overload definitions differ" do
    source = <<-CRYSTAL
      class OverloadedIdentityProbe
        def target(value : Int32) : Int32
          value
        end

        def target(value : String) : Int32
          value.size
        end
      end

      probe = OverloadedIdentityProbe.new
      probe.target(1)
      probe.target("one")
    CRYSTAL

    program, engine = infer_handoff_source(source)
    handoffs = source_resolutions(program, engine)
      .select { |resolution| resolution.arg_types.size == 1 }
      .map { |resolution| CallResolutionHandoff.from(resolution).not_nil! }
    handoffs.size.should eq 2
    handoffs[0].body_key.def_identity.should_not eq handoffs[1].body_key.def_identity
    handoffs[0].body_key.should_not eq handoffs[1].body_key
  end

  it "manually binds the exact handoff only on the same-owner test path" do
    source = <<-CRYSTAL
      class HIRProbe
        def target(value : Int32) : Int32
          value
        end
      end

      probe = HIRProbe.new
      probe.target(1)
    CRYSTAL
    program, engine = infer_handoff_source(source)
    resolution = source_call_ids(program).map { |id| source_resolution_for(program, engine, id) }
      .find { |candidate| candidate.arg_types.size == 1 }.not_nil!
    hir_call = Adamas::HIR::Call.with_receiver(0_u32, Adamas::HIR::TypeRef::INT32, 1_u32, "HIRProbe#target", [2_u32])

    handoff = CallResolutionHandoff.from(resolution).not_nil!
    hir_call.__test_bind_resolution_handoff(handoff)
    hir_call.resolution_handoff.should eq handoff
    hir_call.resolution_handoff.not_nil!.same?(handoff).should be_true
    handoff.resolution_id.should eq resolution.resolution_id
  end

  it "is default-off and leaves synthesized calls nil" do
    source = <<-CRYSTAL
      class DisabledHandoffProbe
        def target(value : Int32) : Int32
          value
        end
      end

      probe = DisabledHandoffProbe.new
      probe.target(1)
    CRYSTAL
    program, engine = infer_handoff_source(source, false)
    engine.semantic_type_context.should be_nil
    source_call_ids(program).each do |id|
      engine.resolution_for(CallsiteIdentity.new(program.ast_arena.object_id.to_u64, id.index)).should be_nil
    end

    synthesized = Adamas::HIR::Call.without_receiver(1_u32, Adamas::HIR::TypeRef::INT32, "synthetic", [] of Adamas::HIR::ValueId)
    synthesized.resolution_handoff.should be_nil
  end

  it "rejects named resolution while default and splat calls stay upstream" do
    source = <<-CRYSTAL
      class UnsupportedHandoffProbe
        def named(*, level : Int32, width : String) : Int32
          level
        end

        def defaulted(value : Int32 = 1) : Int32
          value
        end

        def splatted(*values : Int32) : Int32
          1
        end
      end

      probe = UnsupportedHandoffProbe.new
      probe.named(width: "wide", level: 3)
      probe.defaulted()
      probe.splatted(1, 2)
    CRYSTAL
    program, engine = infer_handoff_source(source)
    source_call_ids(program).size.should eq 3
    resolutions = source_resolutions(program, engine)
    resolutions.size.should eq 1
    resolutions[0].named_arg_types.should_not be_nil
    CallResolutionHandoff.from(resolutions[0]).should be_nil
  end

  it "rejects coordinate-only resolutions at the handoff boundary" do
    arena = Frontend::AstArena.new
    table = SemanticTypeInternTable.new
    scope = ResolutionScope.new(arena, table)
    int32 = table.primitive("Int32")
    resolution = CallResolution.new(
      scope.issue,
      scope,
      table,
      CallsiteIdentity.new(arena.object_id.to_u64, 3),
      DefIdentity.new(arena.object_id.to_u64, 5),
      int32,
      SemanticTypeComponents.new([int32]),
      nil,
    )

    expect_raises(ArgumentError, "CallResolution handoff requires source-backed call and definition coordinates") do
      CallResolutionHandoff.from(resolution)
    end
  end

  it "keeps the body key immutable when exported arrays are mutated" do
    source = <<-CRYSTAL
      class ImmutableHandoffProbe
        def target(value : Int32) : Int32
          value
        end
      end

      probe = ImmutableHandoffProbe.new
      probe.target(1)
    CRYSTAL
    program, engine = infer_handoff_source(source)
    resolution = source_call_ids(program).map { |id| source_resolution_for(program, engine, id) }
      .find { |candidate| candidate.arg_types.size == 1 }.not_nil!
    handoff = CallResolutionHandoff.from(resolution).not_nil!
    handoff.body_key.arg_types.to_a << engine.semantic_type_context.not_nil!.primitive("String")
    handoff.body_key.arg_types.size.should eq 1
  end

  it "retains a lawful handoff on a direct HIR-to-MIR call" do
    source = <<-CRYSTAL
      class DirectMIRProbe
        def target(value : Int32) : Int32
          value
        end
      end

      probe = DirectMIRProbe.new
      probe.target(1)
    CRYSTAL
    program, engine = infer_handoff_source(source)
    resolution = source_resolutions(program, engine)
      .find { |candidate| candidate.arg_types.size == 1 }.not_nil!
    handoff = CallResolutionHandoff.from(resolution).not_nil!
    hir_call = Adamas::HIR::Call.with_receiver(0_u32, Adamas::HIR::TypeRef::INT32, 1_u32, "DirectMIRProbe#target", [2_u32])
    hir_call.__test_bind_resolution_handoff(handoff)

    hir_module = Adamas::HIR::Module.new("t1b0_direct_handoff")
    lowering = Adamas::MIR::HIRToMIRLowering.new(hir_module)
    mir_call = lowering.__test_lower_direct_handoff(hir_call).not_nil!
    mir_call.resolution_handoff.should eq handoff
    mir_call.resolution_handoff.not_nil!.same?(handoff).should be_true
  end

  it "retains a lawful handoff when an optimizer clones a direct call" do
    source = <<-CRYSTAL
      class OptimizerProbe
        def target(value : Int32) : Int32
          value
        end
      end

      probe = OptimizerProbe.new
      probe.target(1)
    CRYSTAL
    program, engine = infer_handoff_source(source)
    resolution = source_call_ids(program).map { |id| source_resolution_for(program, engine, id) }
      .find { |candidate| candidate.arg_types.size == 1 }.not_nil!
    handoff = CallResolutionHandoff.from(resolution).not_nil!
    function = Adamas::MIR::Function.new(0_u32, "__t1b0_optimizer", Adamas::MIR::TypeRef::INT32)
    original = Adamas::MIR::Call.new(1_u32, Adamas::MIR::TypeRef::INT32, 7_u32, [3_u32], nil, nil, handoff)
    clone = Adamas::MIR::CopyPropagationPass.new(function).__test_rewrite_call(
      original,
      {3_u32 => 2_u32},
    )

    clone.args.should eq [2_u32]
    clone.resolution_handoff.should eq handoff
    clone.resolution_handoff.not_nil!.same?(handoff).should be_true
    clone.resolution_handoff.not_nil!.resolution_id.should eq resolution.resolution_id
  end
end
