require "spec"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"

class Adamas::HIR::AstToHir
  def __test_generated_allocator_source_accepts?(name : String, arg_types : Array(Adamas::HIR::TypeRef)) : Bool
    generated_allocator_source_accepts?(name, arg_types)
  end

  def __test_generated_allocator_source_stamp(name : String) : {UInt64, Array(Adamas::HIR::TypeRef)}?
    proof = @generated_allocator_sources[name]?
    proof.try { |entry| {entry[1], entry[5].dup} }
  end

  def __test_repair_stale_call_return_types : Nil
    repair_stale_call_return_types
  end
end

private ALLOCATOR_SOURCE = <<-CRYSTAL
  class AllocatorProofRepairProbe
    def initialize(value : Int32)
      value == 0
    end
  end

  AllocatorProofRepairProbe.new(1)
  CRYSTAL

private def lower_allocator_proof_fixture : Adamas::HIR::AstToHir
  lexer = Adamas::Compiler::Frontend::Lexer.new(ALLOCATOR_SOURCE)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  arena = result.arena
  roots = result.roots

  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => ALLOCATOR_SOURCE},
    paths_by_arena: {arena.object_id.to_u64 => "allocator_proof_repair.cr"},
  )
  converter.arena = arena

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  main_calls = [] of UInt64
  roots.each do |expr_id|
    case node = arena[expr_id]
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::CallNode
      main_calls << expr_id.index.to_u64
    end
  end

  classes.each { |node| converter.register_class(node) }
  classes.each { |node| converter.lower_class(node) }
  converter.lower_main(main_calls) unless main_calls.empty?
  converter.flush_pending_functions
  converter
end

private def allocator_proof_function(converter : Adamas::HIR::AstToHir) : Adamas::HIR::Function
  function = converter.module.functions.find do |candidate|
    candidate.name.starts_with?("AllocatorProofRepairProbe.new$")
  end
  function || raise "generated allocator fixture function was not lowered"
end

private def allocator_initializer_call(function : Adamas::HIR::Function) : Adamas::HIR::Call
  call = function.blocks
    .flat_map(&.instructions)
    .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
    .find { |candidate| candidate.method_name.starts_with?("AllocatorProofRepairProbe#initialize$") }
  call || raise "generated allocator initializer call was not lowered"
end

describe "generated allocator source proof after call result repair" do
  it "keeps the exact source proof current when the allocator initializer call is retyped" do
    converter = lower_allocator_proof_fixture
    allocator = allocator_proof_function(converter)
    initializer_call = allocator_initializer_call(allocator)
    initializer_call.type.should eq(Adamas::HIR::TypeRef::BOOL)

    stamp = converter.__test_generated_allocator_source_stamp(allocator.name)
    stamp.should_not be_nil
    stamp.not_nil![1].should eq([Adamas::HIR::TypeRef::INT32])
    stamp.not_nil![0].should eq(allocator.body_revision)
    converter.__test_generated_allocator_source_accepts?(
      allocator.name,
      [Adamas::HIR::TypeRef::INT32],
    ).should be_true
  end

  it "rejects wrong shapes and does not revive a proof after unrelated mutation" do
    converter = lower_allocator_proof_fixture
    allocator = allocator_proof_function(converter)
    initializer_call = allocator_initializer_call(allocator)
    name = allocator.name

    converter.__test_generated_allocator_source_accepts?(
      name,
      [] of Adamas::HIR::TypeRef,
    ).should be_false
    converter.__test_generated_allocator_source_accepts?(
      name,
      [Adamas::HIR::TypeRef::STRING],
    ).should be_false
    converter.__test_generated_allocator_source_accepts?(
      name,
      [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32],
    ).should be_false
    converter.__test_generated_allocator_source_accepts?(
      name,
      [Adamas::HIR::TypeRef::VOID],
    ).should be_false

    block = allocator.blocks.find do |candidate|
      candidate.instructions.any? { |instruction| instruction.id == initializer_call.id }
    end
    block.should_not be_nil
    body = block.not_nil!
    original_revision = allocator.body_revision
    body.insert(
      0,
      Adamas::HIR::Literal.new(
        allocator.next_value_id,
        Adamas::HIR::TypeRef::BOOL,
        true,
      ),
    )
    allocator.body_revision.should_not eq(original_revision)
    converter.__test_generated_allocator_source_accepts?(name, [Adamas::HIR::TypeRef::INT32]).should be_false

    index = body.instructions.index { |instruction| instruction.id == initializer_call.id }
    index.should_not be_nil
    current_call = body.instructions[index.not_nil!].as(Adamas::HIR::Call)
    void_call = Adamas::HIR::Call.with_receiver_virtual(
      current_call.id,
      Adamas::HIR::TypeRef::VOID,
      current_call.receiver_value,
      current_call.method_name,
      current_call.args.dup,
      current_call.virtual,
    )
    body.replace(index.not_nil!, void_call)
    converter.__test_repair_stale_call_return_types

    repaired_call = allocator_initializer_call(allocator)
    repaired_call.type.should eq(Adamas::HIR::TypeRef::BOOL)
    converter.__test_generated_allocator_source_accepts?(name, [Adamas::HIR::TypeRef::INT32]).should be_false
    converter.__test_generated_allocator_source_stamp(name).not_nil![0].should_not eq(allocator.body_revision)
  end
end
