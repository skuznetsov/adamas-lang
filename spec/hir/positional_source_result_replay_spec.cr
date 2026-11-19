require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def spec_positional_source_result_replay : Nil
    node_type = type_ref_for_name("PositionalReplay::Node")
    producer = "PositionalReplay.literal$PositionalReplay::Node"
    consumer = "PositionalReplay.parse$PositionalReplay::Node"
    expected_facts = [
      {type_ref_for_name("PositionalReplay::Identifier"), false},
      {type_ref_for_name("PositionalReplay::Constant"), false},
    ].sort_by(&.[0].id)
    remember_callsite_arg_types(consumer, [node_type], [false])

    # Lower the actual grouped case at the last available force depth so
    # its call to the selected source body must be captured and replayed.
    @force_lower_return_type_depth = 3
    @force_lower_retry_driver_active = true
    begin
      force_lower_function_for_return_type(consumer)
    ensure
      @force_lower_return_type_depth = 0
      @force_lower_retry_driver_active = false
    end

    request = @force_lower_retry_work.find do |work|
      work.is_a?(ForceLowerSuspendedRequest) && work.name == consumer
    end.as?(ForceLowerSuspendedRequest).not_nil!
    request.pending.producer.should eq(producer)
    live = @pending_arg_types[producer]
    live.source_argument_facts.not_nil!.first.not_nil!.value_facts.should eq(expected_facts)
    replay = request.pending.producer_replay.not_nil!.callsite
    replay.source_argument_facts.should eq(live.source_argument_facts)
    reconciled_force_lower_callsite(live, replay).should eq(replay)

    # Identical carrier and kind are insufficient when another invocation
    # reached the same body with a different set of proven descendants.
    other_facts = [
      {type_ref_for_name("PositionalReplay::Identifier"), false},
      {type_ref_for_name("PositionalReplay::Other"), false},
    ].sort_by(&.[0].id)
    other = replay.with_source_evidence([SourceCallArgument.new(node_type, false, nil, other_facts).as(SourceCallArgument?)], nil)
    reconciled_force_lower_callsite(other, replay).should be_nil
    ordinary_active_body_callsite?(replay).should be_false

    @force_lower_retry_work.clear
    run_force_lower_retry_driver(request).should be_true
    settled_force_lower_result?(producer).should be_true
    settled_force_lower_result?(consumer).should be_true
    @module.function_by_name(consumer).not_nil!.return_type.should eq(TypeRef::INT32)
  end
end

describe "positional source arguments in a suspended result" do
  it "retains the narrowed facts from the actual grouped case call" do
    source = <<-CRYSTAL
      module PositionalReplay
        abstract class Node
        end

        class Identifier < Node
        end

        class Constant < Node
        end

        class Other < Node
        end

        def self.literal(node : Identifier) : Int32?
          65
        end

        def self.literal(node : Constant) : Int32?
          66
        end

        def self.literal(node : Node) : Int32?
          nil
        end

        def self.parse(node : Node) : Int32
          case node
          when Identifier, Constant
            self.literal(node) || 88
          else
            67
          end
        end
      end
      CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    compiler = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    compiler.no_prelude = true
    compiler.register_module(arena[program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode))
    compiler.spec_positional_source_result_replay
  end
end
