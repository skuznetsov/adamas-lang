require "spec"
require "./inherited_primitive_method_binding_spec"

private def lower_stale_primitive_binding_fixture(name : String) : Adamas::HIR::AstToHir
  source = File.read(File.join(__DIR__, "fixtures/inherited_primitive_binding", name))
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
  main = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::LibNode
      converter.register_lib(node)
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

private def stale_primitive_binding_main_calls(converter : Adamas::HIR::AstToHir) : Array(Adamas::HIR::Call)
  main = converter.module.function_by_name("__adamas_main").not_nil!
  main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
end

private def stale_primitive_binding_call(
  converter : Adamas::HIR::AstToHir,
  owner : String,
  method : String,
) : Adamas::HIR::Call
  stale_primitive_binding_main_calls(converter)
    .find { |call| call.method_name.starts_with?("#{owner}##{method}") }
    .not_nil!
end

class Adamas::HIR::AstToHir
  # Test-only access to the canonical receipt validator. The inherited-binding
  # spec's __test_read_primitive_template_binding intentionally reads the raw
  # stored receipt, so stale-receipt assertions must use this validated view.
  def __test_validated_primitive_template_binding(target_name : String)
    if binding = primitive_template_source_binding_for(target_name)
      {
        binding.source_name,
        binding.source_def,
        binding.source_arena,
        binding.template_owner,
        binding.physical_owner,
      }
    end
  end

  # Replace the canonical source registration through the same central
  # registry setters used by production registration. The physical alias and
  # its already-materialized HIR body are deliberately untouched.
  def __test_replace_canonical_primitive_source(
    source_name : String,
    source_def : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
    source_text : String,
  ) : Nil
    set_source_for_arena(source_arena, source_text)
    set_function_def_entry(source_name, source_def, record_current_arena: false)
    set_function_def_arena(source_name, source_arena)
  end

  # Change only the canonical key's arena registration. The source Def object
  # and the physical Int64 alias/body remain unchanged.
  def __test_replace_canonical_primitive_source_arena(
    source_name : String,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
    source_text : String,
  ) : Nil
    set_source_for_arena(source_arena, source_text)
    set_function_def_arena(source_name, source_arena)
  end

  def __test_get_function_return_type_for_stale_source(name : String) : TypeRef
    get_function_return_type(name)
  end

  def __test_reuse_existing_function_body(name : String) : Nil
    lower_function_if_needed(name)
  end
end

private def parse_stale_primitive_floor_copy(
  source : String,
) : Tuple(Adamas::Compiler::Frontend::DefNode, Adamas::Compiler::Frontend::ArenaLike)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  int_node = program.roots.compact_map do |root|
    arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
  end.find do |node|
    String.new(node.name) == "Int"
  end.not_nil!
  floor_def = int_node.body.not_nil!.compact_map do |expr_id|
    arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
  end.find do |node|
    String.new(node.name) == "floor"
  end.not_nil!
  {floor_def, arena}
end

private def assert_primitive_template_source_is_stale(
  converter : Adamas::HIR::AstToHir,
  physical_call : Adamas::HIR::Call,
  original_source_def : Adamas::Compiler::Frontend::DefNode,
  original_source_arena : Adamas::Compiler::Frontend::ArenaLike,
) : Nil
  physical_call.virtual.should be_false
  target = converter.module.function_by_name(physical_call.method_name).not_nil!
  target.blocks.should_not be_empty
  original_target_id = target.id
  original_target_return = target.return_type

  # The raw receipt is retained for diagnosis, but the validated getter must
  # refuse it once its canonical Int#floor source has changed.
  raw = converter.__test_read_primitive_template_binding(physical_call.method_name).not_nil!
  raw[1].same?(original_source_def).should be_true
  raw[2].same?(original_source_arena).should be_true
  converter.__test_validated_primitive_template_binding(physical_call.method_name).should be_nil

  return_error = expect_raises(Adamas::HIR::LoweringError) do
    converter.__test_get_function_return_type_for_stale_source(physical_call.method_name)
  end
  return_error.message.not_nil!.should contain("primitive-template source binding became stale")

  reuse_error = expect_raises(Adamas::HIR::LoweringError) do
    converter.__test_reuse_existing_function_body(physical_call.method_name)
  end
  reuse_error.message.not_nil!.should contain("primitive-template source binding became stale")

  # Validation fails before existing-body reuse, without deleting or replacing
  # the physical specialization that was already emitted.
  same_target = converter.module.function_by_name(physical_call.method_name).not_nil!
  same_target.id.should eq(original_target_id)
  same_target.return_type.should eq(original_target_return)
  same_target.blocks.should_not be_empty
end

describe "primitive-template source freshness" do
  it "keeps a current inherited receipt usable before any canonical-source change" do
    converter = lower_stale_primitive_binding_fixture("inherited_methods.cr")
    source_def, source_arena = converter.__test_primitive_method_source_binding("Int#floor")
    source_def = source_def.not_nil!
    source_arena = source_arena.not_nil!
    call = stale_primitive_binding_call(converter, "Int64", "floor")

    receipt = converter.__test_validated_primitive_template_binding(call.method_name).not_nil!
    receipt[0].should eq("Int#floor")
    receipt[1].same?(source_def).should be_true
    receipt[2].same?(source_arena).should be_true
    receipt[3].should eq("Int")
    receipt[4].should eq("Int64")

    converter.__test_get_function_return_type_for_stale_source(call.method_name)
      .should eq(Adamas::HIR::TypeRef::INT64)
    converter.__test_reuse_existing_function_body(call.method_name)
  end

  it "rejects a replaced canonical Int#floor Def while preserving Int64's body" do
    converter = lower_stale_primitive_binding_fixture("inherited_methods.cr")
    source_def, source_arena = converter.__test_primitive_method_source_binding("Int#floor")
    source_def = source_def.not_nil!
    source_arena = source_arena.not_nil!
    call = stale_primitive_binding_call(converter, "Int64", "floor")

    source_text = File.read(File.join(__DIR__, "fixtures/inherited_primitive_binding/inherited_methods.cr"))
    replacement_def, replacement_arena = parse_stale_primitive_floor_copy(source_text)
    replacement_def.same?(source_def).should be_false
    converter.__test_replace_canonical_primitive_source(
      "Int#floor", replacement_def, replacement_arena, source_text,
    )

    canonical_def, canonical_arena = converter.__test_primitive_method_source_binding("Int#floor")
    canonical_def.not_nil!.same?(replacement_def).should be_true
    canonical_arena.not_nil!.same?(replacement_arena).should be_true
    assert_primitive_template_source_is_stale(converter, call, source_def, source_arena)
  end

  it "rejects a remapped canonical Int#floor arena while preserving its Def and Int64 body" do
    converter = lower_stale_primitive_binding_fixture("inherited_methods.cr")
    source_def, source_arena = converter.__test_primitive_method_source_binding("Int#floor")
    source_def = source_def.not_nil!
    source_arena = source_arena.not_nil!
    call = stale_primitive_binding_call(converter, "Int64", "floor")

    source_text = File.read(File.join(__DIR__, "fixtures/inherited_primitive_binding/inherited_methods.cr"))
    equivalent_def, replacement_arena = parse_stale_primitive_floor_copy(source_text)
    String.new(equivalent_def.name).should eq("floor")
    replacement_arena.same?(source_arena).should be_false
    converter.__test_replace_canonical_primitive_source_arena(
      "Int#floor", replacement_arena, source_text,
    )

    canonical_def, canonical_arena = converter.__test_primitive_method_source_binding("Int#floor")
    canonical_def.not_nil!.same?(source_def).should be_true
    canonical_arena.not_nil!.same?(replacement_arena).should be_true
    assert_primitive_template_source_is_stale(converter, call, source_def, source_arena)
  end
end
