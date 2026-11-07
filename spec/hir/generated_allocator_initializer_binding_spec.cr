require "spec"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"

class Adamas::HIR::AstToHir
  def __test_generated_allocator_initializer_witness(public_source : Bool = false) : {Adamas::HIR::Function, Adamas::HIR::Call, Adamas::HIR::Function, String, String}
    allocator_name = @generated_allocator_layout_recipes.keys.find do |name|
      recipe = @generated_allocator_layout_recipes[name]?
      recipe && recipe.initializer_call && recipe.selected_init_target.nil? == public_source
    end
    raise "generated allocator initializer witness was not recorded" unless allocator_name

    recipe = @generated_allocator_layout_recipes[allocator_name]
    contract = recipe.initializer_call || raise "generated allocator initializer contract was not recorded"
    wrapper = @module.function_by_name(allocator_name) || raise "generated allocator wrapper was not materialized"
    call = wrapper.blocks
      .flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |candidate| candidate.id == contract.id } || raise "generated allocator initializer call was not found"
    selected = contract.source
    target = @module.function_by_name(contract.target_name) || raise "selected initializer target was not materialized"
    {wrapper, call, target, selected.symbol_name, contract.target_name}
  end

  def __test_validate_generated_allocator_initializer(
    wrapper : Adamas::HIR::Function,
    call : Adamas::HIR::Call,
    settled_result : Bool = false,
  ) : Bool
    generated_allocator_initializer_call?(wrapper, call, require_settled_result: settled_result)
  end

  def __test_late_array_value_type : {Adamas::HIR::TypeRef, Adamas::HIR::TypeRef, Adamas::HIR::TypeRef}
    function = @module.create_function("__array_projection", Adamas::HIR::TypeRef::NIL)
    literal = Adamas::HIR::ArrayLiteral.new(function.next_value_id, Adamas::HIR::TypeRef::INT32, [] of Adamas::HIR::ValueId)
    function.blocks.first.add(literal)
    projected = hir_value_type_in_function(function, literal.id) || raise "missing array value"
    collected = collect_function_value_types(function)[literal.id]
    {literal.type, projected, collected}
  end

  def __test_repair_stale_call_return_types : Nil
    repair_stale_call_return_types
  end

  def __test_poison_initializer_base_return(target_name : String) : String
    base_name = strip_type_suffix(target_name)
    @function_types[base_name] = Adamas::HIR::TypeRef::INT32
    base_name
  end

  def __test_retype_generated_allocator_initializer(
    wrapper : Adamas::HIR::Function,
    call : Adamas::HIR::Call,
    result_type : Adamas::HIR::TypeRef,
  ) : Adamas::HIR::Call
    block = wrapper.blocks.find do |candidate|
      candidate.instructions.any? { |instruction| instruction.id == call.id }
    end || raise "generated allocator initializer block was not found"
    index = block.instructions.index { |instruction| instruction.id == call.id } || raise "generated allocator initializer index was not found"
    replacement = Adamas::HIR::Call.with_receiver(
      call.id,
      result_type,
      call.receiver_value,
      call.method_name,
      call.args.dup,
    )
    replace_repaired_result_type(wrapper, block, index, replacement)
    block.instructions[index].as(Adamas::HIR::Call)
  end

  def __test_replace_selected_initializer_def(public_source : Bool = false) : Nil
    allocator_name = @generated_allocator_layout_recipes.keys.find do |name|
      recipe = @generated_allocator_layout_recipes[name]?
      recipe && recipe.initializer_call && recipe.selected_init_target.nil? == public_source
    end || raise "generated allocator initializer witness was not recorded"
    selected = @generated_allocator_layout_recipes[allocator_name].initializer_call.not_nil!.source
    replacement = @function_defs.values.find { |candidate| !candidate.same?(selected.def_node) } ||
                  raise "fixture has no distinct source definition"
    set_function_def_entry(selected.symbol_name, replacement, record_current_arena: false)
  end

  def __test_replace_selected_initializer_arena(public_source : Bool = false) : Nil
    allocator_name = @generated_allocator_layout_recipes.keys.find do |name|
      recipe = @generated_allocator_layout_recipes[name]?
      recipe && recipe.initializer_call && recipe.selected_init_target.nil? == public_source
    end || raise "generated allocator initializer witness was not recorded"
    selected = @generated_allocator_layout_recipes[allocator_name].initializer_call.not_nil!.source
    set_function_def_arena(selected.symbol_name, Adamas::Compiler::Frontend::AstArena.new)
  end

  def __test_replace_initializer_target_function : Nil
    _, _, target, _, target_name = __test_generated_allocator_initializer_witness
    removed = @module.remove_function(target_name)
    raise "selected initializer target could not be removed" unless removed
    replacement = @module.create_function(target_name, target.return_type)
    target.params.each do |param|
      copied = replacement.add_param(param.name, param.type, param.is_block)
      copied.default_literal = param.default_literal
    end
    replacement.blocks.first.terminator = Adamas::HIR::Return.new
  end

  def __test_add_initializer_target_param : Nil
    _, _, target, _, _ = __test_generated_allocator_initializer_witness
    target.add_param("unowned", Adamas::HIR::TypeRef::BOOL)
  end
end

private GENERATED_ALLOCATOR_INITIALIZER_SOURCE = <<-CRYSTAL
  class AllocatorParent
    def initialize(value : Int32 = 65, *, target : Int32? = nil)
    end
  end

  class AllocatorChild < AllocatorParent
    def initialize(message : Int32, *, file : Int32, @other : Int32? = nil)
      return
    end
  end

  class AllocatorGrandchild < AllocatorChild
  end

  AllocatorGrandchild.new(65, file: 66)
  CRYSTAL

private def lower_generated_allocator_initializer_fixture(source : String = GENERATED_ALLOCATOR_INITIALIZER_SOURCE) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "generated_allocator_initializer_binding.cr"},
  )
  converter.no_prelude = true
  converter.arena = arena

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  main = [] of UInt64
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root.index.to_u64
    end
  end
  classes.each { |node| converter.register_class(node) }
  classes.each { |node| converter.lower_class(node) }
  converter.lower_main(main) unless main.empty?
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter
end

describe "generated allocator initializer source binding" do
  it "retains the selected inherited named-only initializer and its exact physical target" do
    converter = lower_generated_allocator_initializer_fixture
    wrapper, call, target, selected_name, target_name = converter.__test_generated_allocator_initializer_witness

    selected_name.should contain("AllocatorChild#initialize")
    target_name.should eq(target.name)
    call.method_name.should eq(target_name)
    target.return_type.should eq(Adamas::HIR::TypeRef::NIL)
    converter.__test_validate_generated_allocator_initializer(wrapper, call).should be_true

    poisoned_base = converter.__test_poison_initializer_base_return(target_name)
    poisoned_base.should_not eq(target_name)
    converter.__test_repair_stale_call_return_types
    wrapper, call, target, _, _ = converter.__test_generated_allocator_initializer_witness
    call.type.should eq(Adamas::HIR::TypeRef::NIL)
    call.type.should eq(target.return_type)
    converter.__test_validate_generated_allocator_initializer(wrapper, call, settled_result: true).should be_true
  end

  it "does not recover a completed physical Void result from a broader source cache" do
    converter = lower_generated_allocator_initializer_fixture
    wrapper, call, target, _, target_name = converter.__test_generated_allocator_initializer_witness
    # Induce the completed physical signature observed in the native reducer.
    # Result-only repair must transport its exact Void result, independently
    # of a wider source/base cache, without granting authority to change ABI.
    target.return_type = Adamas::HIR::TypeRef::VOID
    converter.__test_retype_generated_allocator_initializer(wrapper, call, Adamas::HIR::TypeRef::INT32)
    converter.__test_poison_initializer_base_return(target_name)
    converter.__test_repair_stale_call_return_types

    wrapper, call, target, _, _ = converter.__test_generated_allocator_initializer_witness
    target.return_type.should eq(Adamas::HIR::TypeRef::VOID)
    call.type.should eq(Adamas::HIR::TypeRef::VOID)
    converter.__test_validate_generated_allocator_initializer(wrapper, call, settled_result: true).should be_true
  end

  it "does not let an unrelated same-id call borrow the initializer receipt" do
    converter = lower_generated_allocator_initializer_fixture
    wrapper, call, _, _, _ = converter.__test_generated_allocator_initializer_witness
    unrelated = Adamas::HIR::Call.with_receiver(
      call.id,
      call.type,
      call.receiver_value,
      "Ordinary#initialize$Int32",
      call.args.dup,
    )

    expect_raises(Adamas::HIR::LoweringError, /lost its selected source or ABI/) do
      converter.__test_validate_generated_allocator_initializer(wrapper, unrelated)
    end
  end

  it "rejects a changed source Def or arena instead of reusing the generated body" do
    converter = lower_generated_allocator_initializer_fixture
    wrapper, call, _, _, _ = converter.__test_generated_allocator_initializer_witness
    converter.__test_replace_selected_initializer_def
    expect_raises(Adamas::HIR::LoweringError, /lost its selected source or ABI/) do
      converter.__test_validate_generated_allocator_initializer(wrapper, call)
    end

    converter = lower_generated_allocator_initializer_fixture
    wrapper, call, _, _, _ = converter.__test_generated_allocator_initializer_witness
    converter.__test_replace_selected_initializer_arena
    expect_raises(Adamas::HIR::LoweringError, /lost its selected source or ABI/) do
      converter.__test_validate_generated_allocator_initializer(wrapper, call)
    end
  end

  it "rejects replacement or signature mutation of the physical initializer Function" do
    converter = lower_generated_allocator_initializer_fixture
    wrapper, call, _, _, _ = converter.__test_generated_allocator_initializer_witness
    converter.__test_replace_initializer_target_function
    expect_raises(Adamas::HIR::LoweringError, /lost its selected source or ABI/) do
      converter.__test_validate_generated_allocator_initializer(wrapper, call)
    end

    converter = lower_generated_allocator_initializer_fixture
    wrapper, call, _, _, _ = converter.__test_generated_allocator_initializer_witness
    converter.__test_add_initializer_target_param
    expect_raises(Adamas::HIR::LoweringError, /lost its selected source or ABI/) do
      converter.__test_validate_generated_allocator_initializer(wrapper, call)
    end
  end

  it "rejects stale wrapper-body evidence after an unrelated body mutation" do
    converter = lower_generated_allocator_initializer_fixture
    wrapper, call, _, _, _ = converter.__test_generated_allocator_initializer_witness
    wrapper.blocks.first.insert(
      0,
      Adamas::HIR::Literal.new(wrapper.next_value_id, Adamas::HIR::TypeRef::BOOL, true),
    )

    expect_raises(Adamas::HIR::LoweringError, /lost its selected source or ABI/) do
      converter.__test_validate_generated_allocator_initializer(wrapper, call)
    end
  end

  it "allows an early result to remain unsettled but rejects call or target result drift at the final boundary" do
    converter = lower_generated_allocator_initializer_fixture
    converter.__test_repair_stale_call_return_types
    wrapper, call, target, _, _ = converter.__test_generated_allocator_initializer_witness
    bad_result = target.return_type == Adamas::HIR::TypeRef::BOOL ?
                   Adamas::HIR::TypeRef::INT32 : Adamas::HIR::TypeRef::BOOL
    repaired_call = converter.__test_retype_generated_allocator_initializer(wrapper, call, bad_result)

    # The layout/source receipt remains current after the authorized result-only repair.
    converter.__test_validate_generated_allocator_initializer(wrapper, repaired_call).should be_true
    expect_raises(Adamas::HIR::LoweringError, /lost its selected source or ABI/) do
      converter.__test_validate_generated_allocator_initializer(wrapper, repaired_call, settled_result: true)
    end

    converter = lower_generated_allocator_initializer_fixture
    converter.__test_repair_stale_call_return_types
    wrapper, call, target, _, _ = converter.__test_generated_allocator_initializer_witness
    target.return_type = target.return_type == Adamas::HIR::TypeRef::BOOL ?
                           Adamas::HIR::TypeRef::INT32 : Adamas::HIR::TypeRef::BOOL
    expect_raises(Adamas::HIR::LoweringError, /lost its selected source or ABI/) do
      converter.__test_validate_generated_allocator_initializer(wrapper, call, settled_result: true)
    end
  end
end

private GENERATED_PUBLIC_ALLOCATOR_INITIALIZER_SOURCE = <<-CRYSTAL
  class PublicAllocatorParent
    def self.build(value : Int32?)
      self.new(value)
    end

    def initialize(value : Int32? = nil)
      return
    end
  end

  class PublicAllocatorChild < PublicAllocatorParent
  end

  PublicAllocatorChild.build(65)
  CRYSTAL

describe "canonical generated allocator initializer source binding" do
  it "owns the inherited physical call without promoting its public layout recipe" do
    converter = lower_generated_allocator_initializer_fixture(GENERATED_PUBLIC_ALLOCATOR_INITIALIZER_SOURCE)
    wrapper, call, target, selected_name, target_name = converter.__test_generated_allocator_initializer_witness(public_source: true)
    selected_name.should contain("PublicAllocatorParent#initialize")
    target_name.should eq(target.name)
    converter.__test_validate_generated_allocator_initializer(wrapper, call, settled_result: true).should be_true
  end

  it "rejects stale source Def or arena on a canonical public wrapper" do
    converter = lower_generated_allocator_initializer_fixture(GENERATED_PUBLIC_ALLOCATOR_INITIALIZER_SOURCE)
    wrapper, call, _, _, _ = converter.__test_generated_allocator_initializer_witness(public_source: true)
    converter.__test_replace_selected_initializer_def(public_source: true)
    expect_raises(Adamas::HIR::LoweringError, /lost its selected source or ABI/) do
      converter.__test_validate_generated_allocator_initializer(wrapper, call)
    end

    converter = lower_generated_allocator_initializer_fixture(GENERATED_PUBLIC_ALLOCATOR_INITIALIZER_SOURCE)
    wrapper, call, _, _, _ = converter.__test_generated_allocator_initializer_witness(public_source: true)
    converter.__test_replace_selected_initializer_arena(public_source: true)
    expect_raises(Adamas::HIR::LoweringError, /lost its selected source or ABI/) do
      converter.__test_validate_generated_allocator_initializer(wrapper, call)
    end
  end

  it "uses the same runtime Array(T) projection in direct and collected late facts" do
    converter = lower_generated_allocator_initializer_fixture("class Array(T)\nend\n")
    raw_type, projected, collected = converter.__test_late_array_value_type
    raw_type.should eq(Adamas::HIR::TypeRef::VOID)
    projected.should_not eq(Adamas::HIR::TypeRef::VOID)
    projected.should eq(collected)
    converter.module.get_type_descriptor(projected).not_nil!.name.should eq("Array(Int32)")
  end
end
