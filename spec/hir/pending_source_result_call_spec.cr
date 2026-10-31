require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_pending_call_type_name(type : TypeRef) : String
    get_type_name_from_ref(type)
  end
end

private def pending_call_fixture(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/pending_source_result_call_spec.cr"},
  )
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

private def pending_call_types(converter, owner : String, method : String) : Array(String)
  prefix = "#{owner}##{method}"
  calls = converter.module.functions.flat_map(&.blocks).flat_map(&.instructions)
    .compact_map(&.as?(Adamas::HIR::Call)).select do |call|
    call.method_name == prefix || call.method_name.starts_with?("#{prefix}$")
  end
  functions = converter.module.functions.select do |function|
    function.name == prefix || function.name.starts_with?("#{prefix}$")
  end
  calls.should_not be_empty
  functions.should_not be_empty
  (calls.map(&.type) + functions.map(&.return_type)).map do |type|
    converter.__test_pending_call_type_name(type)
  end
end

describe "pending source method call results" do
  it "keeps Nil and Int32 on a question-mark call before any consumer condition" do
    converter = pending_call_fixture(<<-CRYSTAL)
      struct PendingCallQuestion
        def result(enabled : Bool) : Int32?
          maybe_value?(enabled)
        end
      end
      struct PendingCallQuestion
        private def maybe_value?(enabled : Bool)
          return unless enabled
          65
        end
      end
      PendingCallQuestion.new.result(true)
    CRYSTAL
    pending_call_types(converter, "PendingCallQuestion", "maybe_value?").each do |name|
      name.should contain("Int32")
      name.should contain("Nil")
      name.should_not contain("Bool")
    end
  end

  it "applies the same pending-result contract to a plain method" do
    converter = pending_call_fixture(<<-CRYSTAL)
      struct PendingCallPlain
        def result(enabled : Bool) : Int32?
          maybe_value(enabled)
        end
      end
      struct PendingCallPlain
        private def maybe_value(enabled : Bool)
          return unless enabled
          66
        end
      end
      PendingCallPlain.new.result(false)
    CRYSTAL
    pending_call_types(converter, "PendingCallPlain", "maybe_value").each do |name|
      name.should contain("Int32")
      name.should contain("Nil")
      name.should_not contain("Bool")
    end
  end

  it "preserves the concrete tuple result of a question-mark method" do
    converter = pending_call_fixture(<<-CRYSTAL)
      struct PendingCallTuple
        def result(enabled : Bool) : Tuple(Int32?, Int32?)
          maybe_pair?(enabled)
        end
      end
      struct PendingCallTuple
        private def maybe_pair?(enabled : Bool)
          return {nil, nil} unless enabled
          left = 65
          if enabled
            right = 66
          end
          return left, right
        end
      end
      PendingCallTuple.new.result(true)
    CRYSTAL
    pending_call_types(converter, "PendingCallTuple", "maybe_pair?").each do |name|
      name.should contain("Tuple")
      name.should contain("Int32")
      name.should contain("Nil")
      name.should_not contain("Bool")
    end
  end

  it "keeps a question-mark zero result as Int32" do
    converter = pending_call_fixture(<<-CRYSTAL)
      struct PendingCallZero
        def result : Int32
          zero?
        end
      end
      struct PendingCallZero
        private def zero?
          0
        end
      end
      PendingCallZero.new.result
    CRYSTAL
    pending_call_types(converter, "PendingCallZero", "zero?").each do |name|
      name.should eq("Int32")
    end
  end

  it "keeps a genuine Bool predicate as Bool" do
    converter = pending_call_fixture(<<-CRYSTAL)
      struct PendingCallBool
        def result(flag : Bool) : Bool
          ready?(flag)
        end
      end
      struct PendingCallBool
        private def ready?(flag : Bool)
          flag
        end
      end
      PendingCallBool.new.result(true)
    CRYSTAL
    pending_call_types(converter, "PendingCallBool", "ready?").each do |name|
      name.should eq("Bool")
    end
  end

  it "rejects an undefined question-mark call" do
    expect_raises(Adamas::HIR::LoweringError, /missing_query/) do
      pending_call_fixture(<<-CRYSTAL)
        struct PendingCallUndefined
          def run
            missing_query?
          end
        end
        PendingCallUndefined.new.run
      CRYSTAL
    end
  end

  it "rejects an argument that violates the selected source parameter type" do
    expect_raises(Adamas::HIR::LoweringError, /accepts_integer/) do
      pending_call_fixture(<<-CRYSTAL)
        struct PendingCallArgument
          def accepts_integer?(value : Int32)
            value
          end
        end
        PendingCallArgument.new.accepts_integer?("wrong")
      CRYSTAL
    end
  end
end
