require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

alias CaseCopyCallArgumentObservation = NamedTuple(
  function_name: String,
  call_method_name: String,
  argument_id: String,
  argument_type_name: String,
  source_type_name: String?,
  copy_edges: Array(String),
  source_facts: Array(String),
  argument_facts: Array(String),
  argument_contract_type_name: String,
  argument_contract_type_literal: Bool,
  argument_contract_facts: Array(String)?,
)

class Adamas::HIR::AstToHir
  @@case_copy_call_argument_observations = [] of CaseCopyCallArgumentObservation

  def self.__test_clear_case_copy_call_argument_observations : Nil
    @@case_copy_call_argument_observations.clear
  end

  def self.__test_case_copy_call_argument_observations : Array(CaseCopyCallArgumentObservation)
    @@case_copy_call_argument_observations.dup
  end

  private def case_copy_call_type_name(type : TypeRef?) : String?
    type.try do |type_ref|
      generic_param_type_name_from_ref(type_ref).split(" | ").sort.join(" | ")
    end
  end

  private def case_copy_call_fact_names(facts : Array({TypeRef, Bool})) : Array(String)
    facts.map do |(type_ref, type_literal)|
      type_name = generic_param_type_name_from_ref(type_ref).split(" | ").sort.join(" | ")
      "#{type_name}:#{type_literal}"
    end.sort
  end

  private def case_copy_call_source_name(node_id : Adamas::Compiler::Frontend::ExprId) : String?
    case node = @arena[node_id]
    when Adamas::Compiler::Frontend::IdentifierNode
      safe_slice_to_string(node.name)
    else
      nil
    end
  end

  private def case_copy_call_observe_argument(
    ctx : LoweringContext,
    call : Call,
  ) : Nil
    return unless call.args.size == 1

    argument_id = call.args.first
    argument = source_call_argument(ctx, argument_id)
    argument_facts = source_block_result_value_facts(ctx, argument_id)
    copy_edges = [] of String
    current_id = argument_id
    source_type_name : String? = nil
    source_facts = [] of String

    loop do
      producer = ctx.value_for(current_id)
      copy = producer.try(&.as?(Copy))
      break unless copy

      source_type = ctx.type_of(copy.source)
      destination_type = ctx.type_of(copy.id)
      copy_edges << "#{case_copy_call_type_name(destination_type)} <= #{case_copy_call_type_name(source_type)}"
      if source_type_name.nil? || generic_param_type_name_from_ref(source_type).includes?("CaseCopyCallFactsC")
        source_type_name = case_copy_call_type_name(source_type)
        source_facts = case_copy_call_fact_names(source_block_result_value_facts(ctx, copy.source))
      end
      current_id = copy.source
    end

    @@case_copy_call_argument_observations << {
      function_name: ctx.function.name,
      call_method_name: call.method_name,
      argument_id: argument_id.to_s,
      argument_type_name: case_copy_call_type_name(ctx.type_of(argument_id)).not_nil!,
      source_type_name: source_type_name,
      copy_edges: copy_edges,
      source_facts: source_facts,
      argument_facts: case_copy_call_fact_names(argument_facts),
      argument_contract_type_name: case_copy_call_type_name(argument.type_ref).not_nil!,
      argument_contract_type_literal: argument.type_literal,
      argument_contract_facts: argument.value_facts.try { |facts| case_copy_call_fact_names(facts) },
    }
  end

  private def lower_call(
    ctx : LoweringContext,
    node : Adamas::Compiler::Frontend::CallNode,
    expr_id : ExprId = ExprId.new(-1),
  ) : ValueId
    result = previous_def(ctx, node, expr_id)
    return result unless case_copy_call_source_name(node.callee) == "case_copy_call_target"
    call = ctx.value_for(result).as?(Call)
    case_copy_call_observe_argument(ctx, call) if call
    result
  end
end

private def lower_parsed_case_copy_call_argument_probe : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class CaseCopyCallFactsA
    end

    class CaseCopyCallFactsB
    end

    class CaseCopyCallFactsC
    end

    def case_copy_call_target(value : CaseCopyCallFactsA | CaseCopyCallFactsB) : Int32
      65
    end

    def case_copy_call_probe(value : CaseCopyCallFactsA | CaseCopyCallFactsB | CaseCopyCallFactsC) : Int32
      case value
      when CaseCopyCallFactsA, CaseCopyCallFactsB
        case_copy_call_target(value)
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

describe "parsed case narrowing at a normal call argument" do
  it "passes the real narrowed Copy facts to the unchanged source call consumer" do
    Adamas::HIR::AstToHir.__test_clear_case_copy_call_argument_observations
    lower_parsed_case_copy_call_argument_probe

    observations = Adamas::HIR::AstToHir.__test_case_copy_call_argument_observations
    observations.size.should eq(1)
    observation = observations.first

    expected_source = "CaseCopyCallFactsA | CaseCopyCallFactsB | CaseCopyCallFactsC"
    expected_argument = "CaseCopyCallFactsA | CaseCopyCallFactsB"
    observation[:function_name].should contain("case_copy_call_probe")
    observation[:call_method_name].should contain("case_copy_call_target")
    observation[:source_type_name].should eq(expected_source)
    observation[:source_facts].should_not be_empty
    observation[:source_facts].join(" ").should contain("CaseCopyCallFactsC")
    observation[:copy_edges].should contain("#{expected_argument} <= #{expected_source}")

    # This is the exact argument carried by the normally lowered HIR Call. Its
    # producer is the Copy emitted by the parsed `when A, B` branch, and the
    # unchanged source_call_argument/source_block_result_value_facts consumers
    # must see only the branch's admitted A and B instance alternatives.
    observation[:argument_type_name].should eq(expected_argument)
    observation[:argument_contract_type_name].should eq(expected_argument)
    observation[:argument_contract_type_literal].should be_false
    observation[:argument_facts].should eq([
      "CaseCopyCallFactsA:false",
      "CaseCopyCallFactsB:false",
    ])
    observation[:argument_contract_facts].should eq(observation[:argument_facts])
  end
end
