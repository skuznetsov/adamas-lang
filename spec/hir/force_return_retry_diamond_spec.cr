require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_force_retry_diamond_type_name(type : TypeRef) : String
    get_type_name_from_ref(type)
  end
end

private def force_retry_diamond_fixture(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/force_return_retry_diamond_spec.cr"},
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

private def force_retry_diamond_source(reverse_order : Bool = false, wrong_leaf : Bool = false) : String
  leaf = wrong_leaf ? "true" : "RetryDiamondPayload.new"
  a_body = if reverse_order
             "result = RetryDiamondC.new(value)\nRetryDiamondB.new(value)\nresult"
           else
             "RetryDiamondB.new(value)\nRetryDiamondC.new(value)"
           end
  <<-CRYSTAL
    class RetryDiamondPayload
      def marker : Int32
        65
      end
    end
    class RetryDiamondD
      def self.new(value : T) forall T
        #{leaf}
      end
    end
    class RetryDiamondE
      def self.new(value : T) forall T
        RetryDiamondPayload.new
      end
    end
    class RetryDiamondB
      def self.new(value : T) forall T
        RetryDiamondD.new(value)
      end
    end
    class RetryDiamondC
      def self.new(value : T) forall T
        result = RetryDiamondB.new(value)
        RetryDiamondE.new(value)
        result
      end
    end
    class RetryDiamondA
      def self.new(value : T) forall T
        #{a_body}
      end
    end
    class RetryDiamondOuter0
      def self.new(value : T) forall T
        RetryDiamondA.new(value)
      end
    end
    class RetryDiamondOuter1
      def self.new(value : T) forall T
        RetryDiamondOuter0.new(value)
      end
    end
    class RetryDiamondOuter2
      def self.new(value : T) forall T
        RetryDiamondOuter1.new(value)
      end
    end
    def retry_diamond_observe(value : RetryDiamondPayload) : Int32
      value.marker
    end
    retry_diamond_observe(RetryDiamondOuter2.new(1))
    CRYSTAL
end

private def force_retry_source_result_names(converter, owner : String) : Array(String)
  # Source-selected generic specializations are distinct from any generated
  # zero-argument allocator, which is allowed to retain the nominal owner.
  name = "#{owner}.new$Int32"
  calls = converter.module.functions.flat_map(&.blocks).flat_map(&.instructions)
    .compact_map(&.as?(Adamas::HIR::Call)).select { |call| call.method_name == name }
  functions = converter.module.functions.select { |function| function.name == name }
  calls.should_not be_empty
  functions.size.should eq(1)
  (calls.map(&.type) + functions.map(&.return_type)).map do |type|
    converter.__test_force_retry_diamond_type_name(type)
  end
end

private def force_retry_expect_payload_results(converter) : Nil
  %w(RetryDiamondA RetryDiamondB RetryDiamondC RetryDiamondD RetryDiamondE
    RetryDiamondOuter0 RetryDiamondOuter1 RetryDiamondOuter2).each do |owner|
    force_retry_source_result_names(converter, owner).each do |name|
      name.should eq("RetryDiamondPayload")
    end
  end
end

describe "forced source result replay across a dependency diamond" do
  it "settles a blocked C after its previously queued B dependency settles" do
    converter = force_retry_diamond_fixture(force_retry_diamond_source)
    force_retry_expect_payload_results(converter)
  end

  it "publishes the same result when only A's B and C call order is reversed" do
    converter = force_retry_diamond_fixture(force_retry_diamond_source(reverse_order: true))
    force_retry_expect_payload_results(converter)
  end

  it "rejects a genuinely incompatible leaf after traversing the same generic diamond" do
    expect_raises(Adamas::HIR::LoweringError, /retry_diamond_observe.*Bool/) do
      force_retry_diamond_fixture(force_retry_diamond_source(wrong_leaf: true))
    end
  end

  it "terminates return discovery for mutually recursive generic factories with an established result" do
    converter = force_retry_diamond_fixture(<<-CRYSTAL)
      class RetryCycleA
        def self.new(value : T) : Int32 forall T
          return 65 if value == 0
          RetryCycleB.new(value &- 1)
        end
      end
      class RetryCycleB
        def self.new(value : T) : Int32 forall T
          RetryCycleA.new(value)
        end
      end
      def retry_cycle_observe(value : Int32) : Int32
        value
      end
      retry_cycle_observe(RetryCycleA.new(2))
    CRYSTAL
    %w(RetryCycleA RetryCycleB).each do |owner|
      force_retry_source_result_names(converter, owner).each do |name|
        name.should eq("Int32")
      end
    end
  end
end
