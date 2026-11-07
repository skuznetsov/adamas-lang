require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  # Exercise the normal parsed-source call path with a deliberately shallow
  # force budget. The test restores the budget before normal pending work runs.
  def spec_lower_main_at_depth(main_exprs : Array(UInt64), depth : Int32) : Nil
    @force_lower_return_type_depth = depth
    begin
      lower_main(main_exprs)
    ensure
      @force_lower_return_type_depth = 0
    end
  end

  def spec_replay_state_is_settled? : Bool
    @force_lower_provisional_dependencies.empty? &&
      @force_lower_result_suspensions.empty? &&
      @force_lower_return_type_depth == 0
  end
end

private def lower_sequential_replay_fixture(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.arena = arena

  main = [] of UInt64
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root.index.to_u64
    end
  end

  converter.spec_lower_main_at_depth(main, 0)
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter
end

private def sequential_replay_function(converter : Adamas::HIR::AstToHir, prefix : String) : Adamas::HIR::Function
  converter.module.functions.find do |function|
    function.name.starts_with?(prefix) && !function.blocks.empty?
  end.not_nil!
end

describe "sequential exact-source replay" do
  it "settles a second nested producer discovered while replaying its consumer" do
    source = <<-CRYSTAL
      class ReplayFirst0
        def self.value
          ReplayFirst1.value
        end
      end
      class ReplayFirst1
        def self.value
          ReplayFirst2.value
        end
      end
      class ReplayFirst2
        def self.value
          ReplayFirst3.value
        end
      end
      class ReplayFirst3
        def self.value
          ReplayFirst4.value
        end
      end
      class ReplayFirst4
        def self.value
          65
        end
      end

      class ReplaySecond0
        def self.value
          ReplaySecond1.value
        end
      end
      class ReplaySecond1
        def self.value
          ReplaySecond2.value
        end
      end
      class ReplaySecond2
        def self.value
          ReplaySecond3.value
        end
      end
      class ReplaySecond3
        def self.value
          ReplaySecond4.value
        end
      end
      class ReplaySecond4
        def self.value
          66
        end
      end

      class ReplayConsumer
        def self.value
          ReplayFirst0.value &+ ReplaySecond0.value
        end
      end

      ReplayConsumer.value
      CRYSTAL

    converter = lower_sequential_replay_fixture(source)
    consumer = sequential_replay_function(converter, "ReplayConsumer.value")
    consumer.return_type.should eq(Adamas::HIR::TypeRef::INT32)

    calls = consumer.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
    first = calls.find { |call| call.method_name.starts_with?("ReplayFirst0.value") }
    second = calls.find { |call| call.method_name.starts_with?("ReplaySecond0.value") }
    first.should_not be_nil
    second.should_not be_nil
    first.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)
    second.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)

    sequential_replay_function(converter, "ReplayFirst4.value").return_type.should eq(Adamas::HIR::TypeRef::INT32)
    sequential_replay_function(converter, "ReplaySecond4.value").return_type.should eq(Adamas::HIR::TypeRef::INT32)
    converter.spec_replay_state_is_settled?.should be_true
  end
end
