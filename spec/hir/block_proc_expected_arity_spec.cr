require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_refine_arity_proc_capture(owner : String, proc_name : String, observed_return : String) : Nil
    refine_captured_initializer_proc_type(owner, type_ref_for_name(proc_name), type_ref_for_name(observed_return))
  end
end

private def lower_block_proc_expected_arity(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  converter.arena = program.arena
  converter.no_prelude = true

  main = [] of UInt64
  program.roots.each do |root|
    next unless root
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root.index.to_u64
    end
  end

  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

private def block_proc_signatures(converter : Adamas::HIR::AstToHir) : Array(Array(Adamas::HIR::TypeRef))
  converter.module.functions
    .select { |function| function.name.starts_with?("__crystal_block_proc_") }
    .map do |function|
      function.params.reject { |param| param.name == "__closure_env" }.map(&.type)
    end
end

describe "block Proc expected argument ABI" do
  it "keeps unnamed and ignored trailing expected inputs in the generated Proc ABI" do
    converter = lower_block_proc_expected_arity(<<-CRYSTAL)
      class OneArgumentCallbackHolder
        def initialize(&@callback : Int32 -> Nil)
        end
      end

      class TwoArgumentCallbackHolder
        def initialize(&@callback : Int32, String -> Nil)
        end
      end

      OneArgumentCallbackHolder.new { }
      OneArgumentCallbackHolder.new { |value| value }
      TwoArgumentCallbackHolder.new { |value| value }
      TwoArgumentCallbackHolder.new { |value, suffix| value }
    CRYSTAL

    signatures = block_proc_signatures(converter)
    signatures.should contain([Adamas::HIR::TypeRef::INT32])
    signatures.count { |signature| signature == [Adamas::HIR::TypeRef::INT32] }.should eq(2)
    signatures.should contain([Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::STRING])
    signatures.count { |signature| signature == [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::STRING] }.should eq(2)
    callbacks = converter.module.functions.select { |function| function.name.starts_with?("__crystal_block_proc_") }
    callbacks.map(&.return_type).should eq(Array.new(4, Adamas::HIR::TypeRef::NIL))
  end

  it "does not erase incompatible arguments or an actual non-Nil return contract" do
    converter = lower_block_proc_expected_arity(<<-CRYSTAL)
      class ArityNilDestination
        def initialize(&@callback : Int32 -> Nil)
        end
      end
      class ArityValueDestination
        def initialize(&@callback : Int32 -> Bool)
        end
      end
    CRYSTAL

    converter.__test_refine_arity_proc_capture("ArityNilDestination", "Proc(Int32, Nil)", "Float64")
    expect_raises(Exception, /captured initializer Proc ABI conflict/) do
      converter.__test_refine_arity_proc_capture("ArityNilDestination", "Proc(String, Nil)", "Nil")
    end
    expect_raises(Exception, /captured initializer Proc ABI conflict/) do
      converter.__test_refine_arity_proc_capture("ArityNilDestination", "Proc(Int32, Float64)", "Float64")
    end
    expect_raises(Exception, /captured initializer Proc ABI conflict/) do
      converter.__test_refine_arity_proc_capture("ArityValueDestination", "Proc(Int32, Int32)", "Int32")
    end
  end

  it "preserves an explicitly empty Proc input list for captured callbacks" do
    converter = lower_block_proc_expected_arity(<<-CRYSTAL)
      class CapturedFiber
        def initialize(&@proc : -> Bool)
        end

        def run : Bool
          @proc.call
        end
      end

      CapturedFiber.new { true }
      CapturedFiber.new { false }
    CRYSTAL

    block_proc_signatures(converter).should contain([] of Adamas::HIR::TypeRef)
    empty_input_functions = converter.module.functions.select do |function|
      function.name.starts_with?("__crystal_block_proc_") &&
        function.params.reject { |param| param.name == "__closure_env" }.empty?
    end
    empty_input_functions.count { |function| function.return_type == Adamas::HIR::TypeRef::BOOL }.should eq(2)
  end

  it "uses initialize's block contract when a registered self.new has no matching call shape" do
    converter = lower_block_proc_expected_arity(<<-CRYSTAL)
      class DirectShapeAllocator
        def self.new(label : String, &block : Int32 -> Int32)
          self
        end
      end

      class ShapeAwareAllocator
        def self.new(label : String? = nil, &block : Int32 -> Int32)
          self
        end

        def initialize(label : String, count : Int32, &@proc : -> Bool)
        end
      end

      DirectShapeAllocator.new("compatible") { |value| value }
      ShapeAwareAllocator.new("fiber", 3) { true }
    CRYSTAL

    block_functions = converter.module.functions.select do |function|
      function.name.starts_with?("__crystal_block_proc_")
    end
    block_functions.any? do |function|
      function.params.reject { |param| param.name == "__closure_env" }.map(&.type) == [Adamas::HIR::TypeRef::INT32] &&
        function.return_type == Adamas::HIR::TypeRef::INT32
    end.should be_true
    block_functions.any? do |function|
      function.params.reject { |param| param.name == "__closure_env" }.empty? &&
        function.return_type == Adamas::HIR::TypeRef::BOOL
    end.should be_true
  end

  it "uses initialize only when a registered self.new does not match the current call shape" do
    converter = lower_block_proc_expected_arity(<<-CRYSTAL)
      class StaleShapeAllocator
        def self.new(label : String? = nil, &block : String -> Int32)
          self
        end

        def initialize(label : String, count : Int32, &@proc : Int32 -> Bool)
        end
      end

      class MatchingShapeAllocator
        def self.new(label : String, &block : Char -> String)
          self
        end
      end

      StaleShapeAllocator.new("warmup") { |label| 42 }
      StaleShapeAllocator.new("fiber", 3) { true }
      MatchingShapeAllocator.new("direct") { |char| char.to_s }
    CRYSTAL

    block_functions = converter.module.functions.select do |function|
      function.name.starts_with?("__crystal_block_proc_")
    end
    block_functions.any? do |function|
      function.params.reject { |param| param.name == "__closure_env" }.map(&.type) == [Adamas::HIR::TypeRef::INT32] &&
        function.return_type == Adamas::HIR::TypeRef::BOOL
    end.should be_true
    block_functions.any? do |function|
      function.params.reject { |param| param.name == "__closure_env" }.map(&.type) == [Adamas::HIR::TypeRef::STRING] &&
        function.return_type == Adamas::HIR::TypeRef::INT32
    end.should be_true
    block_functions.any? do |function|
      function.params.reject { |param| param.name == "__closure_env" }.map(&.type) == [Adamas::HIR::TypeRef::CHAR] &&
        function.return_type == Adamas::HIR::TypeRef::STRING
    end.should be_true
  end
end
