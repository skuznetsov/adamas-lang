require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"

class Adamas::HIR::AstToHir
  def __test_lower_hash_annotation_identity(
    expr_id : Adamas::Compiler::Frontend::ExprId,
    owner : String,
  ) : Adamas::HIR::TypeRef
    previous_class = @current_class
    previous_namespace = @current_namespace_override
    @current_class = owner
    @current_namespace_override = nil

    function = @module.create_function("__test_hash_annotation_#{expr_id.index}", TypeRef::VOID)
    ctx = LoweringContext.new(function, @module, @arena)
    value_id = lower_expr(ctx, expr_id)
    ctx.type_of(value_id)
  ensure
    @current_class = previous_class
    @current_namespace_override = previous_namespace
  end

  def __test_infer_hash_annotation_identity(
    expr_id : Adamas::Compiler::Frontend::ExprId,
    owner : String,
  ) : Adamas::HIR::TypeRef
    previous_class = @current_class
    previous_namespace = @current_namespace_override
    @current_class = owner
    @current_namespace_override = nil
    infer_type_from_expr(expr_id, owner) || TypeRef::VOID
  ensure
    @current_class = previous_class
    @current_namespace_override = previous_namespace
  end

  def __test_composite_annotation_binding_identity(
    name : String,
    owner : String,
    signature_scan : Bool,
  ) : Adamas::HIR::TypeRef
    previous_class = @current_class
    previous_namespace = @current_namespace_override
    previous_map = @type_param_map
    previous_scan = @signature_scan_mode
    begin
      @current_class = owner
      @current_namespace_override = nil
      @type_param_map = {"T" => "::Signal"}
      @signature_scan_mode = signature_scan
      @subst_cache_gen &+= 1
      resolved = resolve_composite_type_argument_in_context(name)
      type_ref_for_name(resolved)
    ensure
      @current_class = previous_class
      @current_namespace_override = previous_namespace
      @type_param_map = previous_map
      @signature_scan_mode = previous_scan
      @subst_cache_gen &+= 1
    end
  end

  def __test_hash_annotation_identity_descriptor(type : Adamas::HIR::TypeRef) : Adamas::HIR::TypeDescriptor?
    @module.get_type_descriptor(type)
  end

  def __test_hash_annotation_identity_type_ref(name : String, owner : String) : Adamas::HIR::TypeRef
    previous_class = @current_class
    previous_namespace = @current_namespace_override
    @current_class = owner
    @current_namespace_override = nil
    type_ref_for_name(name)
  ensure
    @current_class = previous_class
    @current_namespace_override = previous_namespace
  end
end

private def hash_annotation_root_identity_fixture : Tuple(
  Adamas::HIR::AstToHir,
  Adamas::Compiler::Frontend::AstArena,
  Hash(String, Adamas::Compiler::Frontend::ExprId),
)
  source = <<-CRYSTAL
    enum Signal
      Ready
    end

    module Crystal::System::Signal
      module Signal
      end

      @@root_key = {} of ::Signal => Int32
      @@root_value = {} of Int32 => ::Signal
      @@relative_key = {} of Signal => Int32
      @@relative_value = {} of Int32 => Signal
      alias Handler = ::Signal ->
      @@root_proc_value = {} of ::Signal => Handler
      @@direct_proc_value = {} of ::Signal => Proc(::Signal, Nil)
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.arena = arena
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::EnumNode
      converter.register_enum(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end

  expressions = {} of String => Adamas::Compiler::Frontend::ExprId
  index = 0
  while index < arena.size
    node_id = Adamas::Compiler::Frontend::ExprId.new(index)
    if assignment = arena[node_id].as?(Adamas::Compiler::Frontend::AssignNode)
      if target = arena[assignment.target].as?(Adamas::Compiler::Frontend::ClassVarNode)
        cvar_name = String.new(target.name).lstrip('@')
        if arena[assignment.value].is_a?(Adamas::Compiler::Frontend::HashLiteralNode)
          expressions[cvar_name] = assignment.value
        end
      end
    end
    index += 1
  end

  {converter, arena, expressions}
end

private def assert_hash_annotation_root_identity(
  converter : Adamas::HIR::AstToHir,
  hash_type : Adamas::HIR::TypeRef,
  key_type : Adamas::HIR::TypeRef,
  value_type : Adamas::HIR::TypeRef,
)
  descriptor = converter.__test_hash_annotation_identity_descriptor(hash_type).not_nil!
  descriptor.kind.should eq(Adamas::HIR::TypeKind::Hash)
  descriptor.type_params.size.should eq(2)
  descriptor.type_params[0].should eq(key_type)
  descriptor.type_params[1].should eq(value_type)
end

private def assert_hash_annotation_root_proc_value(
  converter : Adamas::HIR::AstToHir,
  hash_type : Adamas::HIR::TypeRef,
  root_signal : Adamas::HIR::TypeRef,
  nil_type : Adamas::HIR::TypeRef,
)
  hash_descriptor = converter.__test_hash_annotation_identity_descriptor(hash_type).not_nil!
  hash_descriptor.kind.should eq(Adamas::HIR::TypeKind::Hash)
  hash_descriptor.type_params.size.should eq(2)
  hash_descriptor.type_params[0].should eq(root_signal)

  proc_type = hash_descriptor.type_params[1]
  proc_descriptor = converter.__test_hash_annotation_identity_descriptor(proc_type).not_nil!
  proc_descriptor.kind.should eq(Adamas::HIR::TypeKind::Proc)
  proc_descriptor.type_params.size.should eq(2)
  proc_descriptor.type_params[0].should eq(root_signal)
  proc_descriptor.type_params[1].should eq(nil_type)
end

describe "root-qualified Hash annotation identity" do
  it "preserves explicit root types and resolves relative shadow types during Hash lowering" do
    converter, _arena, expressions = hash_annotation_root_identity_fixture
    owner = "Crystal::System::Signal"
    root_signal = converter.__test_hash_annotation_identity_type_ref("::Signal", owner)
    nested_signal = converter.__test_hash_annotation_identity_type_ref("::Crystal::System::Signal::Signal", owner)
    int32 = converter.__test_hash_annotation_identity_type_ref("Int32", owner)
    nil_type = converter.__test_hash_annotation_identity_type_ref("Nil", owner)
    root_signal.should_not eq(nested_signal)

    root_key = converter.__test_lower_hash_annotation_identity(expressions["root_key"], owner)
    assert_hash_annotation_root_identity(converter, root_key, root_signal, int32)

    root_value = converter.__test_lower_hash_annotation_identity(expressions["root_value"], owner)
    assert_hash_annotation_root_identity(converter, root_value, int32, root_signal)

    relative_key = converter.__test_lower_hash_annotation_identity(expressions["relative_key"], owner)
    assert_hash_annotation_root_identity(converter, relative_key, nested_signal, int32)

    relative_value = converter.__test_lower_hash_annotation_identity(expressions["relative_value"], owner)
    assert_hash_annotation_root_identity(converter, relative_value, int32, nested_signal)

  end

  it "uses the same rooted and relative identities in general Hash expression inference" do
    converter, _arena, expressions = hash_annotation_root_identity_fixture
    owner = "Crystal::System::Signal"
    root_signal = converter.__test_hash_annotation_identity_type_ref("::Signal", owner)
    nested_signal = converter.__test_hash_annotation_identity_type_ref("::Crystal::System::Signal::Signal", owner)
    int32 = converter.__test_hash_annotation_identity_type_ref("Int32", owner)
    nil_type = converter.__test_hash_annotation_identity_type_ref("Nil", owner)
    root_signal.should_not eq(nested_signal)

    root_key = converter.__test_infer_hash_annotation_identity(expressions["root_key"], owner)
    assert_hash_annotation_root_identity(converter, root_key, root_signal, int32)

    root_value = converter.__test_infer_hash_annotation_identity(expressions["root_value"], owner)
    assert_hash_annotation_root_identity(converter, root_value, int32, root_signal)

    relative_key = converter.__test_infer_hash_annotation_identity(expressions["relative_key"], owner)
    assert_hash_annotation_root_identity(converter, relative_key, nested_signal, int32)

    relative_value = converter.__test_infer_hash_annotation_identity(expressions["relative_value"], owner)
    assert_hash_annotation_root_identity(converter, relative_value, int32, nested_signal)

  end
end

describe "root-qualified Proc components in Hash annotations" do
  {"root_proc_value", "direct_proc_value"}.each do |expression|
    {false, true}.each do |inference|
      it "preserves #{expression} during #{inference ? "inference" : "lowering"}" do
        converter, _arena, expressions = hash_annotation_root_identity_fixture
        owner = "Crystal::System::Signal"
        root_signal = converter.__test_hash_annotation_identity_type_ref("::Signal", owner)
        nil_type = converter.__test_hash_annotation_identity_type_ref("Nil", owner)
        hash_type = if inference
                      converter.__test_infer_hash_annotation_identity(expressions[expression], owner)
                    else
                      converter.__test_lower_hash_annotation_identity(expressions[expression], owner)
                    end
        assert_hash_annotation_root_proc_value(converter, hash_type, root_signal, nil_type)
      end
    end
  end
end

describe "root-qualified actuals substituted into composite annotations" do
  {false, true}.each do |signature_scan|
    {"T" => "::Signal", "Tuple(T)" => "::Tuple(::Signal)",
     "Proc(T, Nil)" => "::Proc(::Signal, ::Nil)", "T?" => "::Signal?",
     "T*" => "::Signal*"}.each do |source, expected_name|
      it "keeps #{source} bound to the root identity with signature scan #{signature_scan}" do
        converter, _arena, _expressions = hash_annotation_root_identity_fixture
        owner = "Crystal::System::Signal"
        expected = converter.__test_hash_annotation_identity_type_ref(expected_name, owner)
        actual = converter.__test_composite_annotation_binding_identity(source, owner, signature_scan)
        actual.should eq(expected)
      end
    end
  end
end
