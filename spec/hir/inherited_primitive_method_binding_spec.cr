require "spec"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

private def lower_inherited_primitive_binding_fixture(name : String) : Adamas::HIR::AstToHir
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

class Adamas::HIR::AstToHir
  @@test_nested_floor_binding_observing = false
  @@test_nested_floor_binding_observations = [] of Tuple(
    String,
    String?,
    Adamas::Compiler::Frontend::DefNode?,
    Adamas::Compiler::Frontend::ArenaLike?,
    String?,
    String?,
  )

  def self.__test_nested_floor_binding_begin : Nil
    @@test_nested_floor_binding_observations.clear
    @@test_nested_floor_binding_observing = true
  end

  def self.__test_nested_floor_binding_end : Array(Tuple(
      String,
      String?,
      Adamas::Compiler::Frontend::DefNode?,
      Adamas::Compiler::Frontend::ArenaLike?,
      String?,
      String?,
    ))
    @@test_nested_floor_binding_observing = false
    @@test_nested_floor_binding_observations.dup
  end

  def __test_read_primitive_template_binding(name : String)
    # Observe the canonical source receipt directly; a physical Def alias is
    # not required for source identity.
    if binding = @primitive_template_source_bindings[name]?
      {
        binding.source_name,
        binding.source_def,
        binding.source_arena,
        binding.template_owner,
        binding.physical_owner,
      }
    end
  end

  private def lower_function_if_needed(name : String, trace_site_line : Int32 = __LINE__) : Nil
    if @@test_nested_floor_binding_observing && name.starts_with?("Int64#floor")
      # Capture the exact template receipt before normal lookup or fallback.
      if binding = __test_read_primitive_template_binding(name)
        @@test_nested_floor_binding_observations << {
          name,
          binding[0],
          binding[1],
          binding[2],
          binding[3],
          binding[4],
        }
      else
        @@test_nested_floor_binding_observations << {name, nil, nil, nil, nil, nil}
      end
    end
    previous_def(name, trace_site_line)
  end

  def __test_primitive_method_source_binding(name : String)
    if binding = __test_read_primitive_template_binding(name)
      {binding[1], binding[2]}
    else
      {@function_defs[name]?, @function_def_arenas[name]?}
    end
  end
end

private def primitive_binding_main_calls(converter : Adamas::HIR::AstToHir) : Array(Adamas::HIR::Call)
  main = converter.module.function_by_name("__adamas_main").not_nil!
  main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
end

private def primitive_binding_call(
  converter : Adamas::HIR::AstToHir,
  owner : String,
  method : String,
) : Adamas::HIR::Call
  primitive_binding_main_calls(converter)
    .find { |call| call.method_name.starts_with?("#{owner}##{method}") }
    .not_nil!
end

describe "inherited primitive method source binding" do
  it "binds Int#floor and another inherited method to Int32 and Int64 specializations" do
    converter = lower_inherited_primitive_binding_fixture("inherited_methods.cr")
    base_floor = converter.__test_primitive_method_source_binding("Int#floor").first.not_nil!
    base_marker = converter.__test_primitive_method_source_binding("Int#inherited_marker").first.not_nil!

    {"Int32", "Int64"}.each do |owner|
      floor_call = primitive_binding_call(converter, owner, "floor")
      marker_call = primitive_binding_call(converter, owner, "inherited_marker")
      floor_call.virtual.should be_false
      marker_call.virtual.should be_false

      floor_target = converter.module.function_by_name(floor_call.method_name).not_nil!
      marker_target = converter.module.function_by_name(marker_call.method_name).not_nil!
      floor_target.return_type.should eq(owner == "Int32" ? Adamas::HIR::TypeRef::INT32 : Adamas::HIR::TypeRef::INT64)
      marker_target.return_type.should eq(Adamas::HIR::TypeRef::INT32)

      floor_source, floor_arena = converter.__test_primitive_method_source_binding(floor_call.method_name)
      marker_source, marker_arena = converter.__test_primitive_method_source_binding(marker_call.method_name)
      floor_source.should_not be_nil
      marker_source.should_not be_nil
      floor_source.not_nil!.same?(base_floor).should be_true
      marker_source.not_nil!.same?(base_marker).should be_true
      floor_arena.not_nil!.should be(converter.arena)
      marker_arena.not_nil!.should be(converter.arena)
    end
  end

  it "keeps a concrete Int64 override separate from inherited Int#floor" do
    converter = lower_inherited_primitive_binding_fixture("override_result.cr")
    base_floor = converter.__test_primitive_method_source_binding("Int#floor").first.not_nil!
    int64_override = converter.__test_primitive_method_source_binding("Int64#floor").first.not_nil!

    int32_floor = primitive_binding_call(converter, "Int32", "floor")
    int64_floor = primitive_binding_call(converter, "Int64", "floor")
    int32_target = converter.module.function_by_name(int32_floor.method_name).not_nil!
    int64_target = converter.module.function_by_name(int64_floor.method_name).not_nil!

    int32_target.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    int64_target.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    int32_floor.method_name.should start_with("Int32#floor")
    int64_floor.method_name.should start_with("Int64#floor")
    int32_floor.method_name.should_not eq(int64_floor.method_name)

    int32_source, int32_arena = converter.__test_primitive_method_source_binding(int32_floor.method_name)
    int64_source, int64_arena = converter.__test_primitive_method_source_binding(int64_floor.method_name)
    int32_source.should_not be_nil
    int64_source.should_not be_nil
    int32_source.not_nil!.same?(base_floor).should be_true
    int64_source.not_nil!.same?(int64_override).should be_true
    int32_source.not_nil!.same?(int64_source.not_nil!).should be_false
    int32_source.not_nil!.span.start_offset.should be < int64_source.not_nil!.span.start_offset
    int32_arena.not_nil!.should be(converter.arena)
    int64_arena.not_nil!.should be(converter.arena)
  end

  it "preserves inherited nilary and concrete required-argument overloads" do
    converter = lower_inherited_primitive_binding_fixture("required_arity_shadow.cr")
    base_marker = converter.__test_primitive_method_source_binding("Int#inherited_marker").first.not_nil!
    calls = primitive_binding_main_calls(converter).select do |call|
      call.method_name.includes?("inherited_marker")
    end
    nilary_call = calls.find { |call| call.args.empty? }.not_nil!
    required_call = calls.find { |call| call.args.size == 1 }.not_nil!

    nilary_call.virtual.should be_false
    required_call.virtual.should be_false
    nilary_call.method_name.should_not eq(required_call.method_name)

    nilary_target = converter.module.function_by_name(nilary_call.method_name).not_nil!
    required_target = converter.module.function_by_name(required_call.method_name).not_nil!
    nilary_target.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    required_target.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    nilary_target.id.should_not eq(required_target.id)

    inherited_binding = converter.__test_read_primitive_template_binding(nilary_call.method_name).not_nil!
    inherited_binding[0].should start_with("Int#inherited_marker")
    inherited_binding[1].same?(base_marker).should be_true
    inherited_binding[2].same?(converter.arena).should be_true
    inherited_binding[3].should eq("Int")
    inherited_binding[4].should eq("Int64")

    overload_source, overload_arena = converter.__test_primitive_method_source_binding(required_call.method_name)
    overload_source.should_not be_nil
    overload_source.not_nil!.same?(base_marker).should be_false
    overload_source.not_nil!.params.not_nil!.size.should eq(1)
    overload_arena.not_nil!.should be(converter.arena)
  end

  it "binds inherited floor before a nested factory result is consumed" do
    Adamas::HIR::AstToHir.__test_nested_floor_binding_begin
    converter = lower_inherited_primitive_binding_fixture("nested_factory_tuple.cr")
    observations = Adamas::HIR::AstToHir.__test_nested_floor_binding_end

    base_floor = converter.__test_primitive_method_source_binding("Int#floor").first.not_nil!
    first_nested_floor = observations.find { |entry| entry[0].starts_with?("Int64#floor") }.not_nil!
    first_nested_floor[1].not_nil!.should start_with("Int#floor")
    first_nested_floor[2].not_nil!.same?(base_floor).should be_true
    first_nested_floor[3].not_nil!.same?(converter.arena).should be_true
    first_nested_floor[4].should eq("Int")
    first_nested_floor[5].should eq("Int64")

    factory = converter.module.functions.find do |function|
      function.name.starts_with?("PrimitiveBindingFactory.make")
    end.not_nil!
    tuple_type = converter.module.get_type_descriptor(factory.return_type).not_nil!
    tuple_type.kind.should eq(Adamas::HIR::TypeKind::Tuple)
    tuple_type.type_params.size.should eq(2)
    tuple_type.type_params[0].should eq(Adamas::HIR::TypeRef::INT64)
    tuple_type.type_params[1].should eq(Adamas::HIR::TypeRef::INT32)

    floor_call = factory.blocks
      .flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name.starts_with?("Int64#floor") }
      .not_nil!
    floor_call.virtual.should be_false
    floor_target = converter.module.function_by_name(floor_call.method_name).not_nil!
    floor_target.blocks.should_not be_empty
    floor_target.return_type.should eq(Adamas::HIR::TypeRef::INT64)
  end
end
