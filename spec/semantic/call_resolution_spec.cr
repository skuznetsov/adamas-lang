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

include Adamas::Compiler
include Adamas::Compiler::Semantic

private def infer_call_resolution_source(source : String, capture_call_resolutions : Bool? = true)
  lexer = Frontend::Lexer.new(source)
  parser = Frontend::Parser.new(lexer)
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names

  engine = if capture = capture_call_resolutions
             Semantic::TypeInferenceEngine.new(
               program,
               name_result.identifier_symbols,
               analyzer.global_context.symbol_table,
               capture_call_resolutions: capture,
             )
           else
             Semantic::TypeInferenceEngine.new(
               program,
               name_result.identifier_symbols,
               analyzer.global_context.symbol_table,
             )
           end
  engine.infer_types
  {program, engine, analyzer}
end

private def call_resolution_for(
  program : Frontend::Program,
  engine : Semantic::TypeInferenceEngine,
  expr_id : Frontend::ExprId,
)
  engine.resolution_for(
    CallsiteIdentity.new(program.ast_arena.object_id.to_u64, expr_id.index),
  )
end

private def call_resolution_context_fixture
  source = <<-CRYSTAL
    class ContextProbe
      def target(value : Int32) : Int32
        value
      end
    end

    probe = ContextProbe.new
    probe.target(1)
  CRYSTAL
  program, engine, _analyzer = infer_call_resolution_source(source)
  call_id = program.roots.find { |expr_id| program.ast_arena[expr_id].is_a?(Frontend::CallNode) }.not_nil!
  resolution = call_resolution_for(program, engine, call_id).not_nil!
  {program, call_id, resolution}
end

describe "semantic call resolution" do
  it "is disabled by default without changing legacy inference" do
    source = <<-CRYSTAL
      class DisabledProbe
        def target(value : Int32) : Int32
          value
        end
      end

      probe = DisabledProbe.new
      probe.target(1)
    CRYSTAL

    program, engine, _analyzer = infer_call_resolution_source(source, nil)
    call_id = program.roots.find { |expr_id| program.ast_arena[expr_id].is_a?(Frontend::CallNode) }.not_nil!

    engine.semantic_type_context.should be_nil
    call_resolution_for(program, engine, call_id).should be_nil
    engine.context.get_type(call_id).not_nil!.to_s.should eq "Int32"
  end

  it "exposes owner-scoped identities for ordinary overload, block, and named calls" do
    source = <<-CRYSTAL
      class Probe
        def pick(value : Int32) : Int32
          value
        end

        def pick(value : String) : String
          value
        end

        def with_block(value : Int32, &block : Int32 -> Object) : Int32
          yield value
        end

        def named(*, level : Int32, width : String) : Int32
          level
        end
      end

      probe = Probe.new
      probe.pick(1)
      probe.pick("x")
      probe.with_block(2) { |value| value + 1 }
      probe.named(width: "wide", level: 3)
    CRYSTAL

    program, engine, _analyzer = infer_call_resolution_source(source)
    call_ids = program.roots.select { |expr_id| program.ast_arena[expr_id].is_a?(Frontend::CallNode) }
    call_ids.size.should eq 4

    resolutions = call_ids.map { |expr_id| call_resolution_for(program, engine, expr_id).not_nil! }
    semantic_types = engine.semantic_type_context.not_nil!

    resolutions.map(&.resolution_id).uniq.size.should eq 4
    resolutions.map(&.def_identity).uniq.size.should eq 4
    resolutions[0].arg_types.map { |type_id| semantic_types.normalized_name(type_id) }.should eq ["Int32"]
    resolutions[1].arg_types.map { |type_id| semantic_types.normalized_name(type_id) }.should eq ["String"]
    semantic_types.normalized_name(resolutions[2].block_type.not_nil!).should eq "Proc(Int32, Int32)"
    named = resolutions[3].named_arg_types.not_nil!
    named.size.should eq 2
    semantic_types.names.lookup(named[0][0]).should eq "width"
    semantic_types.names.lookup(named[1][0]).should eq "level"
    named[0][0].should_not eq NameId::UNKNOWN
    named[0][1].should eq resolutions[3].arg_types[1]
    named[1][1].should eq resolutions[3].arg_types[0]

    second_program, second_engine, _second_analyzer = infer_call_resolution_source(source)
    second_call_id = second_program.roots.find { |expr_id| second_program.ast_arena[expr_id].is_a?(Frontend::CallNode) }.not_nil!
    second_resolution = call_resolution_for(second_program, second_engine, second_call_id).not_nil!
    resolutions[0].resolution_id.should_not eq second_resolution.resolution_id
    resolutions[0].callsite.arena_id.should_not eq second_resolution.callsite.arena_id
  end

  it "fails closed for an unsupported named-tuple argument" do
    source = <<-CRYSTAL
      class UnsupportedProbe
        def consume(value) : Int32
          1
        end
      end

      probe = UnsupportedProbe.new
      probe.consume({key: 1})
    CRYSTAL

    program, engine, _analyzer = infer_call_resolution_source(source)
    call_id = program.roots.find { |expr_id| program.ast_arena[expr_id].is_a?(Frontend::CallNode) }.not_nil!

    call_resolution_for(program, engine, call_id).should be_nil
    engine.context.get_type(call_id).not_nil!.to_s.should eq "Int32"
  end

  it "fails closed for default and splat expansion while preserving inferred results" do
    source = <<-CRYSTAL
      class ExpandedProbe
        def defaulted(value : Int32 = 1) : Int32
          value
        end

        def splatted(*values : Int32) : Int32
          1
        end
      end

      probe = ExpandedProbe.new
      probe.defaulted()
      probe.splatted(1, 2)
    CRYSTAL

    program, engine, _analyzer = infer_call_resolution_source(source)
    call_ids = program.roots.select { |expr_id| program.ast_arena[expr_id].is_a?(Frontend::CallNode) }
    call_ids.size.should eq 2

    call_ids.each do |call_id|
      call_resolution_for(program, engine, call_id).should be_nil
      engine.context.get_type(call_id).not_nil!.to_s.should eq "Int32"
    end
  end

  it "records a generic method only from its concrete semantic call arguments" do
    source = <<-CRYSTAL
      class GenericProbe
        def consume(value : T) : Int32
          1
        end
      end

      probe = GenericProbe.new
      probe.consume(7)
    CRYSTAL

    program, engine, _analyzer = infer_call_resolution_source(source)
    call_ids = program.roots.select { |expr_id| program.ast_arena[expr_id].is_a?(Frontend::CallNode) }
    call_ids.size.should eq 1

    resolution = call_resolution_for(program, engine, call_ids[0]).not_nil!
    semantic_types = engine.semantic_type_context.not_nil!
    resolution.arg_types.map { |type_id| semantic_types.normalized_name(type_id) }.should eq ["Int32"]
    engine.context.get_type(call_ids[0]).not_nil!.to_s.should eq "Int32"
  end

  it "rejects a callsite whose explicit identity disagrees with its ExprId" do
    program, call_id, source_resolution = call_resolution_context_fixture
    context = CallResolutionContext.new(program.ast_arena)
    result = context.record(
      call_id,
      CallsiteIdentity.new(program.ast_arena.object_id.to_u64, call_id.index + 1),
      source_resolution.def_identity,
      PrimitiveType.new("Int32"),
      [] of Type,
    )
    invalid_def_result = context.record(
      call_id,
      CallsiteIdentity.new(program.ast_arena.object_id.to_u64, call_id.index),
      DefIdentity.new(program.ast_arena.object_id.to_u64, program.ast_arena.size + 100),
      PrimitiveType.new("Int32"),
      [] of Type,
    )

    result.should be_nil
    invalid_def_result.should be_nil
    context.resolution_scope.issue.id.should eq 0_u64
  end

  it "does not retrieve a local resolution through a foreign arena identity" do
    program, call_id, source_resolution = call_resolution_context_fixture
    context = CallResolutionContext.new(program.ast_arena)
    local_callsite = CallsiteIdentity.new(program.ast_arena.object_id.to_u64, call_id.index)
    resolution = context.record(
      call_id,
      local_callsite,
      source_resolution.def_identity,
      PrimitiveType.new("Int32"),
      [] of Type,
    ).not_nil!

    context[local_callsite].should eq resolution
    context[CallsiteIdentity.new(program.ast_arena.object_id.to_u64 + 1, call_id.index)].should be_nil
  end

  it "does not turn a synthetic builtin node id into a DefIdentity" do
    source = <<-CRYSTAL
      class SyntheticProbe
      end

      probe = SyntheticProbe.new
      probe.hash()
    CRYSTAL

    program, engine, _analyzer = infer_call_resolution_source(source)
    call_id = program.roots.find { |expr_id| program.ast_arena[expr_id].is_a?(Frontend::CallNode) }.not_nil!

    call_resolution_for(program, engine, call_id).should be_nil
    engine.context.get_type(call_id).not_nil!.to_s.should eq "UInt64"
  end

  it "distinguishes equal nominal spellings by source declaration identity" do
    source = <<-CRYSTAL
      module Left
        class Shared
        end
      end

      module Right
        class Shared
        end
      end
    CRYSTAL

    program, _engine, analyzer = infer_call_resolution_source(source)
    global = analyzer.global_context.symbol_table
    left = global.lookup_local("Left").as(ModuleSymbol)
    right = global.lookup_local("Right").as(ModuleSymbol)
    left_shared = left.scope.lookup_local("Shared").as(ClassSymbol)
    right_shared = right.scope.lookup_local("Shared").as(ClassSymbol)
    table = SemanticTypeInternTable.new
    encoder = SemanticTypeEncoder.new(table, program.ast_arena)

    left_id = encoder.encode(ClassType.new(left_shared))
    right_id = encoder.encode(ClassType.new(right_shared))
    alternate_id = table.nominal(
      "AliasShared",
      TypeKind::Class,
      TypeDeclarationIdentity.new(program.ast_arena.object_id.to_u64, left_shared.node_id.index),
      [] of SemanticTypeId,
    )
    foreign_table = SemanticTypeInternTable.new
    foreign_id = foreign_table.nominal(
      "Shared",
      TypeKind::Class,
      TypeDeclarationIdentity.new(program.ast_arena.object_id.to_u64, left_shared.node_id.index),
      [] of SemanticTypeId,
    )

    left_id.should_not eq right_id
    alternate_id.should eq left_id
    table.lookup(left_id).not_nil!.should_not eq foreign_table.lookup(foreign_id).not_nil!
    table.normalized_name(left_id).should eq "Shared"
    table.normalized_name(right_id).should eq "Shared"
    expect_raises(UnsupportedSemanticTypeError) do
      encoder.encode(TypeParameter.new("T"))
    end
  end

  it "rejects a ResolutionId issued by a different scope" do
    arena = Frontend::AstArena.new
    table = SemanticTypeInternTable.new
    issuing_scope = ResolutionScope.new(arena, table)
    foreign_scope = ResolutionScope.new(arena, table)
    int32 = table.primitive("Int32")

    expect_raises(ArgumentError, /foreign, raw, or UNKNOWN ResolutionId/) do
      CallResolution.new(
        issuing_scope.issue,
        foreign_scope,
        table,
        CallsiteIdentity.new(arena.object_id.to_u64, 3),
        DefIdentity.new(arena.object_id.to_u64, 5),
        int32,
        SemanticTypeComponents.new([] of SemanticTypeId),
        nil,
      )
    end
  end

  it "rejects call and definition arenas outside the resolution scope" do
    arena = Frontend::AstArena.new
    foreign_arena = Frontend::AstArena.new
    table = SemanticTypeInternTable.new
    scope = ResolutionScope.new(arena, table)
    int32 = table.primitive("Int32")

    expect_raises(ArgumentError, /arena owners do not match/) do
      CallResolution.new(
        scope.issue,
        scope,
        table,
        CallsiteIdentity.new(foreign_arena.object_id.to_u64, 3),
        DefIdentity.new(foreign_arena.object_id.to_u64, 5),
        int32,
        SemanticTypeComponents.new([] of SemanticTypeId),
        nil,
      )
    end
  end

  it "rejects semantic type IDs from a different compile context" do
    arena = Frontend::AstArena.new
    scope_table = SemanticTypeInternTable.new
    foreign_table = SemanticTypeInternTable.new
    scope = ResolutionScope.new(arena, scope_table)

    rejected_id = scope.issue
    expect_raises(ArgumentError, /not owned by the CallResolution semantic context/) do
      CallResolution.new(
        rejected_id,
        scope,
        scope_table,
        CallsiteIdentity.new(arena.object_id.to_u64, 3),
        DefIdentity.new(arena.object_id.to_u64, 5),
        foreign_table.primitive("Int32"),
        SemanticTypeComponents.new([] of SemanticTypeId),
        nil,
      )
    end

    expect_raises(ArgumentError, /already been claimed/) do
      CallResolution.new(
        rejected_id,
        scope,
        scope_table,
        CallsiteIdentity.new(arena.object_id.to_u64, 3),
        DefIdentity.new(arena.object_id.to_u64, 5),
        scope_table.primitive("Int32"),
        SemanticTypeComponents.new([] of SemanticTypeId),
        nil,
      )
    end

    valid_type = scope_table.primitive("Int32")
    recovered = CallResolution.new(
      scope.issue,
      scope,
      scope_table,
      CallsiteIdentity.new(arena.object_id.to_u64, 3),
      DefIdentity.new(arena.object_id.to_u64, 5),
      valid_type,
      SemanticTypeComponents.new([] of SemanticTypeId),
      nil,
    )
    recovered.resolution_id.id.should eq 1_u64
  end

  it "rejects replaying one ResolutionId with different call facts" do
    arena = Frontend::AstArena.new
    table = SemanticTypeInternTable.new
    scope = ResolutionScope.new(arena, table)
    resolution_id = scope.issue
    int32 = table.primitive("Int32")
    arg_types = SemanticTypeComponents.new([] of SemanticTypeId)

    CallResolution.new(
      resolution_id,
      scope,
      table,
      CallsiteIdentity.new(arena.object_id.to_u64, 3),
      DefIdentity.new(arena.object_id.to_u64, 5),
      int32,
      arg_types,
      nil,
    )

    expect_raises(ArgumentError, /already been claimed/) do
      CallResolution.new(
        resolution_id,
        scope,
        table,
        CallsiteIdentity.new(arena.object_id.to_u64, 4),
        DefIdentity.new(arena.object_id.to_u64, 6),
        int32,
        arg_types,
        nil,
      )
    end
  end
end
