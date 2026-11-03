require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

alias CaseTypeSetCopyObservation = NamedTuple(
  function_name: String,
  local_name: String,
  target_names: Array(String),
  target_kinds: Array(String),
  formal_id: String?,
  before_id: String?,
  after_id: String?,
  copy_source_id: String?,
  formal_type_name: String?,
  before_type_name: String?,
  before_alias_ids: Array(String),
  before_producer_trace: Array(String),
  registered_before_facts: Array(String)?,
  resolved_before_facts: Array(String),
  registered_after_facts: Array(String)?,
  resolved_after_facts: Array(String),
  after_type_literal: Bool?,
)

alias CaseTypeSetProducerObservation = NamedTuple(
  source_type_name: String,
  input_value_id: String,
  before_type_name: String?,
  registered_before_facts: Array(String)?,
  resolved_before_facts: Array(String),
  target_names: Array(String),
  target_kind: Bool,
  copy_value_id: String?,
  copy_source_id: String?,
  registered_after_facts: Array(String)?,
  resolved_after_facts: Array(String),
  after_type_literal: Bool?,
)

class Adamas::HIR::AstToHir
  @@case_type_set_copy_observations = [] of CaseTypeSetCopyObservation

  def self.__test_clear_case_type_set_copy_observations : Nil
    @@case_type_set_copy_observations.clear
  end

  def self.__test_case_type_set_copy_observations : Array(CaseTypeSetCopyObservation)
    @@case_type_set_copy_observations.dup
  end

  def __test_case_condition_type_name(node : Adamas::Compiler::Frontend::Node) : String?
    case_condition_type_name(node)
  end

  def __test_case_type_set_copy_producer(
    source_names : Array(String),
    source_facts : Array({String, Bool}),
    target_names : Array(String),
    target_kind : Bool,
  ) : CaseTypeSetProducerObservation
    source_type_name = source_names.sort.join(" | ")
    source_type = create_union_type(source_type_name)
    function = @module.create_function("__test_case_type_set_copy_producer", TypeRef::VOID)
    parameter = function.add_param("value", source_type)
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.register_type(parameter.id, source_type)
    ctx.register_local("value", parameter.id)

    exact_input_facts = source_facts.map do |(name, type_literal)|
      {type_ref_for_name(name), type_literal}
    end
    ctx.register_source_value_facts(parameter.id, exact_input_facts)

    # Capture explicit input evidence before invoking the real producer. This
    # keeps these checks scoped to case filtering, not the upstream formal
    # source-fact construction path.
    registered_before_facts = case_copy_fact_names(ctx.source_value_facts(parameter.id))
    resolved_before_facts = source_block_result_value_facts(ctx, parameter.id)
      .map { |(type, literal)| "#{generic_param_type_name_from_ref(type)}:#{literal}" }
      .sort
    before_type_name = case_copy_type_name(ctx.type_of(parameter.id))

    targets = target_names.map do |name|
      IsANarrowingTarget.new("value", type_ref_for_name(name), target_kind)
    end
    apply_case_type_set_narrowing(ctx, "value", targets)

    copy_id = ctx.lookup_local("value").not_nil!
    copy = ctx.value_for(copy_id).as?(Copy)
    registered_after_facts = case_copy_fact_names(ctx.source_value_facts(copy_id))
    resolved_after_facts = source_block_result_value_facts(ctx, copy_id)
      .map { |(type, literal)| "#{generic_param_type_name_from_ref(type)}:#{literal}" }
      .sort

    {
      source_type_name: source_type_name,
      input_value_id: parameter.id.to_s,
      before_type_name: before_type_name,
      registered_before_facts: registered_before_facts,
      resolved_before_facts: resolved_before_facts,
      target_names: target_names.sort,
      target_kind: target_kind,
      copy_value_id: copy.try(&.id.to_s),
      copy_source_id: copy.try(&.source.to_s),
      registered_after_facts: registered_after_facts,
      resolved_after_facts: resolved_after_facts,
      after_type_literal: ctx.type_literal?(copy_id),
    }
  end

  private def case_copy_alias_ids(ctx : LoweringContext, start_id : ValueId) : Array(String)
    result = [] of String
    seen = Set(ValueId).new
    current_id = start_id
    loop do
      break unless seen.add?(current_id)
      result << current_id.to_s
      break if ctx.function.params.any? { |param| param.id == current_id }
      producer = ctx.value_for(current_id)
      if copy = producer.as?(Copy)
        current_id = copy.source
      else
        break
      end
    end
    result
  end

  private def case_copy_producer_trace(
    ctx : LoweringContext,
    start_id : ValueId,
    formal_id : ValueId?,
    formal_name : String,
  ) : Array(String)
    result = [] of String
    seen = Set(ValueId).new
    current_id = start_id
    loop do
      break unless seen.add?(current_id)
      if formal_id == current_id
        result << "#{current_id}=formal(#{formal_name})"
        break
      elsif param = ctx.function.params.find { |entry| entry.id == current_id }
        result << "#{current_id}=other-formal(#{param.name})"
        break
      end
      producer = ctx.value_for(current_id)
      if copy = producer.as?(Copy)
        result << "#{current_id}=Copy(#{copy.source})"
        current_id = copy.source
      else
        result << "#{current_id}=#{producer.try(&.class.name) || "no-emitted-producer"}"
        break
      end
    end
    result
  end

  private def case_copy_fact_names(facts : Array({TypeRef, Bool})?) : Array(String)?
    facts.try do |entries|
      entries.map { |(type, literal)| "#{generic_param_type_name_from_ref(type)}:#{literal}" }.sort
    end
  end

  private def case_copy_type_name(type : TypeRef?) : String?
    type.try do |ref|
      generic_param_type_name_from_ref(ref).split(" | ").sort.join(" | ")
    end
  end

  private def apply_case_type_set_narrowing(
    ctx : LoweringContext,
    name : String,
    targets : Array(IsANarrowingTarget),
  ) : Nil
    before_id = ctx.lookup_local(name)
    target_names = targets.map { |target| generic_param_type_name_from_ref(target.type) }.sort
    target_kinds = targets.map do |target|
      case target.type_literal
      when true
        "class"
      when false
        "instance"
      else
        "unknown"
      end
    end.sort

    previous_def(ctx, name, targets)

    if name == "value" && targets.size == 2
      after_id = ctx.lookup_local(name)
      copy_source_id = if after_id
                         ctx.value_for(after_id).as?(Copy).try(&.source).try(&.to_s) || "missing"
                       else
                         "missing"
                       end
      resolved_facts = source_block_result_value_facts(ctx, after_id)
        .map { |(type, literal)| "#{generic_param_type_name_from_ref(type)}:#{literal}" }
        .sort
      formal = ctx.function.params.find { |param| param.name == name }
      formal_id = formal.try(&.id.to_s)
      formal_type_name = formal.try { |param| case_copy_type_name(param.type) }
      before_type_name = before_id.try { |id| case_copy_type_name(ctx.type_of(id)) }
      before_alias_ids = before_id.try { |id| case_copy_alias_ids(ctx, id) } || [] of String
      formal_value_id = formal.try(&.id)
      before_producer_trace = before_id.try do |id|
        case_copy_producer_trace(ctx, id, formal_value_id, name)
      end || [] of String
      registered_before_facts = before_id.try { |id| case_copy_fact_names(ctx.source_value_facts(id)) }
      resolved_before_facts = source_block_result_value_facts(ctx, before_id)
        .map { |(type, literal)| "#{generic_param_type_name_from_ref(type)}:#{literal}" }
        .sort
      registered_after_facts = after_id.try { |id| case_copy_fact_names(ctx.source_value_facts(id)) }

      @@case_type_set_copy_observations << {
        function_name: ctx.function.name,
        local_name: name,
        target_names: target_names,
        target_kinds: target_kinds,
        formal_id: formal_id,
        before_id: before_id.try(&.to_s),
        after_id: after_id.try(&.to_s),
        copy_source_id: copy_source_id,
        formal_type_name: formal_type_name,
        before_type_name: before_type_name,
        before_alias_ids: before_alias_ids,
        before_producer_trace: before_producer_trace,
        registered_before_facts: registered_before_facts,
        resolved_before_facts: resolved_before_facts,
        registered_after_facts: registered_after_facts,
        resolved_after_facts: resolved_facts,
        after_type_literal: after_id.try { |id| ctx.type_literal?(id) },
      }
    end
  end
end

private def lower_parsed_case_type_set_copy_probe
  source = <<-CRYSTAL
    class CopyNarrowFactsA
    end

    class CopyNarrowFactsB
    end

    class CopyNarrowFactsC
    end

    class CopyNarrowFactsParent
    end

    class CopyNarrowFactsChild < CopyNarrowFactsParent
    end

    def case_copy_narrowing_probe(value : CopyNarrowFactsA | CopyNarrowFactsB | CopyNarrowFactsC)
      case value
      when CopyNarrowFactsA, CopyNarrowFactsB
        value
      else
        0
      end
    end

    def case_copy_unknown_relation_probe(value : CopyNarrowFactsParent | CopyNarrowFactsB | CopyNarrowFactsC)
      case value
      when CopyNarrowFactsChild, CopyNarrowFactsB
        value
      else
        0
      end
    end
    CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty

  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  definitions = [] of Adamas::Compiler::Frontend::DefNode
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
      definitions << node
    end
  end

  definitions.each { |definition| converter.lower_def(definition) }
  converter
end

private def parsed_case_condition_type_name(source : String) : String?
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty

  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  program.roots.each do |root|
    if class_node = program.arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(class_node)
    end
  end

  case_root = program.roots.find do |root|
    program.arena[root].is_a?(Adamas::Compiler::Frontend::CaseNode)
  end.not_nil!
  case_node = program.arena[case_root].as(Adamas::Compiler::Frontend::CaseNode)
  condition_id = case_node.when_branches.first.conditions.first
  converter.__test_case_condition_type_name(program.arena[condition_id])
end

private def parsed_case_condition_receiver_shape(source : String) : String
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty

  case_root = program.roots.find do |root|
    program.arena[root].is_a?(Adamas::Compiler::Frontend::CaseNode)
  end.not_nil!
  case_node = program.arena[case_root].as(Adamas::Compiler::Frontend::CaseNode)
  condition_id = case_node.when_branches.first.conditions.first
  member = program.arena[condition_id].as?(Adamas::Compiler::Frontend::MemberAccessNode)
  return "not-member-access" unless member

  receiver = program.arena[member.object]
  case receiver
  when Adamas::Compiler::Frontend::IdentifierNode
    "MemberAccessNode(IdentifierNode:#{String.new(receiver.name)})"
  when Adamas::Compiler::Frontend::PathNode
    "MemberAccessNode(PathNode)"
  when Adamas::Compiler::Frontend::GenericNode
    "MemberAccessNode(GenericNode)"
  else
    "MemberAccessNode(#{receiver.class.name})"
  end
end

describe "case type-set Copy source facts" do
  it "recognizes the stock static .class case target" do
    source = <<-CRYSTAL
      class CaseTargetSyntaxOwner
      end

      case CaseTargetSyntaxOwner
      when CaseTargetSyntaxOwner.class
        65
      end
      CRYSTAL
    parsed_case_condition_receiver_shape(source).should eq(
      "MemberAccessNode(IdentifierNode:CaseTargetSyntaxOwner)")
    parsed_case_condition_type_name(source).should eq("CaseTargetSyntaxOwner.class")
  end

  it "preserves .metaclass as a dynamic method call" do
    parsed_case_condition_type_name(<<-CRYSTAL).should be_nil
      class CaseTargetSyntaxOwner
        def self.metaclass
          7
        end
      end

      case 7
      when CaseTargetSyntaxOwner.metaclass
        65
      end
      CRYSTAL
  end

  it "does not infer a static class target from a runtime call receiver" do
    parsed_case_condition_type_name(<<-CRYSTAL).should be_nil
      class CaseTargetSyntaxOwner
      end

      def case_target_syntax_factory
        CaseTargetSyntaxOwner.new
      end

      case CaseTargetSyntaxOwner.new
      when case_target_syntax_factory.class
        65
      end
      CRYSTAL
  end

  it "observes the production Copy before requiring the narrowed semantic facts" do
    Adamas::HIR::AstToHir.__test_clear_case_type_set_copy_observations
    lower_parsed_case_type_set_copy_probe

    observations = Adamas::HIR::AstToHir.__test_case_type_set_copy_observations
    target_observations = observations.select do |observation|
      observation[:function_name].starts_with?("case_copy_narrowing_probe") &&
        observation[:local_name] == "value" &&
        observation[:target_names] == ["CopyNarrowFactsA", "CopyNarrowFactsB"]
    end
    target_observations.size.should eq(1)
    observation = target_observations.first

    # Establish the real producer ran and emitted a Copy from the original
    # parameter before interpreting any source-fact result.
    observation[:formal_id].should_not be_nil
    observation[:before_id].should_not be_nil
    observation[:before_id].should_not eq(observation[:formal_id])
    observation[:after_id].should_not be_nil
    observation[:copy_source_id].should eq(observation[:before_id])
    observation[:before_alias_ids].first.should eq(observation[:before_id])
    observation[:before_alias_ids].last.should eq(observation[:formal_id])

    expected_source_carrier = "CopyNarrowFactsA | CopyNarrowFactsB | CopyNarrowFactsC"
    observation[:formal_type_name].should eq(expected_source_carrier)
    observation[:before_type_name].should eq(expected_source_carrier)
    # Keep the source carrier's facts separate from the narrowed result. They
    # are evidence about the input before the case producer runs.
    observation[:resolved_before_facts].should_not be_empty

    expected_narrowed_facts = ["CopyNarrowFactsA:false", "CopyNarrowFactsB:false"]
    observation[:resolved_before_facts].should_not eq(observation[:resolved_after_facts])
    observation[:registered_after_facts].should eq(expected_narrowed_facts)
    observation[:resolved_after_facts].should eq(expected_narrowed_facts)
  end

  # These producer-only checks seed exact facts immediately before the real
  # narrowing helper. They do not claim that the upstream mixed-formal path
  # preserves a class alternative; that end-to-end path remains open.
  it "filters explicit mixed instance and class facts in the real case producer" do
    converter = lower_parsed_case_type_set_copy_probe
    observation = converter.__test_case_type_set_copy_producer(
      ["CopyNarrowFactsA", "CopyNarrowFactsB"],
      [
        {"CopyNarrowFactsA", false},
        {"CopyNarrowFactsA", true},
        {"CopyNarrowFactsB", false},
      ],
      ["CopyNarrowFactsA", "CopyNarrowFactsB"],
      false,
    )

    observation[:source_type_name].should eq("CopyNarrowFactsA | CopyNarrowFactsB")
    observation[:before_type_name].should eq(observation[:source_type_name])
    observation[:registered_before_facts].should eq([
      "CopyNarrowFactsA:false",
      "CopyNarrowFactsA:true",
      "CopyNarrowFactsB:false",
    ])
    observation[:resolved_before_facts].should eq(observation[:registered_before_facts].not_nil!)
    observation[:target_names].should eq(["CopyNarrowFactsA", "CopyNarrowFactsB"])
    observation[:target_kind].should be_false
    observation[:copy_value_id].should_not be_nil
    observation[:copy_value_id].should_not eq(observation[:input_value_id])
    observation[:copy_source_id].should eq(observation[:input_value_id])
    observation[:registered_after_facts].should eq([
      "CopyNarrowFactsA:false",
      "CopyNarrowFactsB:false",
    ])
    observation[:resolved_after_facts].should eq(observation[:registered_after_facts].not_nil!)
    observation[:after_type_literal].should be_false
  end

  it "filters all-class facts and marks the Copy from its retained facts" do
    converter = lower_parsed_case_type_set_copy_probe
    observation = converter.__test_case_type_set_copy_producer(
      ["CopyNarrowFactsA", "CopyNarrowFactsB", "CopyNarrowFactsC"],
      [
        {"CopyNarrowFactsA", true},
        {"CopyNarrowFactsB", true},
        {"CopyNarrowFactsC", true},
      ],
      ["CopyNarrowFactsA", "CopyNarrowFactsB"],
      true,
    )

    observation[:before_type_name].should eq(observation[:source_type_name])
    observation[:registered_before_facts].should eq([
      "CopyNarrowFactsA:true",
      "CopyNarrowFactsB:true",
      "CopyNarrowFactsC:true",
    ])
    observation[:resolved_before_facts].should eq(observation[:registered_before_facts].not_nil!)
    observation[:target_names].should eq(["CopyNarrowFactsA", "CopyNarrowFactsB"])
    observation[:target_kind].should be_true
    observation[:copy_value_id].should_not be_nil
    observation[:copy_value_id].should_not eq(observation[:input_value_id])
    observation[:copy_source_id].should eq(observation[:input_value_id])
    observation[:registered_after_facts].should eq([
      "CopyNarrowFactsA:true",
      "CopyNarrowFactsB:true",
    ])
    observation[:resolved_after_facts].should eq(observation[:registered_after_facts].not_nil!)
    observation[:after_type_literal].should be_true
  end

  it "records an empty filter even when the Copy keeps the same carrier" do
    converter = lower_parsed_case_type_set_copy_probe
    observation = converter.__test_case_type_set_copy_producer(
      ["CopyNarrowFactsA", "CopyNarrowFactsB"],
      [
        {"CopyNarrowFactsA", true},
        {"CopyNarrowFactsB", true},
      ],
      ["CopyNarrowFactsA", "CopyNarrowFactsB"],
      false,
    )

    observation[:before_type_name].should eq(observation[:source_type_name])
    observation[:resolved_before_facts].should eq([
      "CopyNarrowFactsA:true",
      "CopyNarrowFactsB:true",
    ])
    observation[:copy_value_id].should_not be_nil
    observation[:copy_value_id].should_not eq(observation[:input_value_id])
    observation[:copy_source_id].should eq(observation[:input_value_id])
    observation[:registered_after_facts].should eq([] of String)
    observation[:resolved_after_facts].should eq([] of String)
    observation[:after_type_literal].should be_false
  end

  it "does not recover filtered source facts through a different-carrier Copy" do
    converter = lower_parsed_case_type_set_copy_probe
    observation = converter.__test_case_type_set_copy_producer(
      ["CopyNarrowFactsA", "CopyNarrowFactsB", "CopyNarrowFactsC"],
      [{"CopyNarrowFactsC", false}],
      ["CopyNarrowFactsA", "CopyNarrowFactsB"],
      false,
    )

    observation[:before_type_name].should eq("CopyNarrowFactsA | CopyNarrowFactsB | CopyNarrowFactsC")
    observation[:resolved_before_facts].should eq(["CopyNarrowFactsC:false"])
    observation[:copy_value_id].should_not be_nil
    observation[:copy_source_id].should eq(observation[:input_value_id])
    observation[:registered_after_facts].should eq([] of String)
    observation[:resolved_after_facts].should eq([] of String)
    observation[:after_type_literal].should be_false
  end

  it "retains an ancestor source fact when its relation to a target is unknown" do
    Adamas::HIR::AstToHir.__test_clear_case_type_set_copy_observations
    lower_parsed_case_type_set_copy_probe

    observation = Adamas::HIR::AstToHir.__test_case_type_set_copy_observations.find do |entry|
      entry[:function_name].starts_with?("case_copy_unknown_relation_probe")
    end.not_nil!
    observation[:target_names].should eq(["CopyNarrowFactsB", "CopyNarrowFactsChild"])
    observation[:resolved_after_facts].should eq(["CopyNarrowFactsB:false", "CopyNarrowFactsParent:false"])
    observation[:resolved_after_facts].should_not contain("CopyNarrowFactsChild:false")
  end
end
