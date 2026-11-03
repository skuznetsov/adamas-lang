require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_source_block_result_value_facts(
    ctx : LoweringContext,
    value : ValueId?,
  ) : Array({TypeRef, Bool})
    source_block_result_value_facts(ctx, value)
  end

  def __test_source_argument_value_name(ctx : LoweringContext, value : ValueId) : String
    proc_source_type_name(source_call_argument(ctx, value))
  end
end

private def source_block_result_value_facts_fixture
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new("")
  )
  parsed = parser.parse_program
  parser.diagnostics.should be_empty

  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  function = converter.module.create_function(
    "__source_block_result_value_facts_probe",
    Adamas::HIR::TypeRef::VOID,
  )
  ctx = Adamas::HIR::LoweringContext.new(function, converter.module, parsed.arena)
  {converter, ctx, function}
end

describe "source block result value facts" do
  it "preserves both instance and type-literal leaves through Phi, UnionWrap, and Copy" do
    converter, ctx, function = source_block_result_value_facts_fixture
    box_type = converter.module.intern_type(
      Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "SourceBlockFacts::Box")
    )
    union_type = converter.module.intern_type(
      Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Union,
        "SourceBlockFacts::Box | Nil",
        [box_type, Adamas::HIR::TypeRef::NIL],
      )
    )

    instance = function.add_param("instance", box_type)
    ctx.register_type(instance.id, box_type)
    class_literal = function.add_param("class_literal", box_type)
    ctx.register_type(class_literal.id, box_type)
    ctx.mark_type_literal(class_literal.id)

    wrapped_instance = Adamas::HIR::UnionWrap.new(
      function.next_value_id, union_type, instance.id, box_type.id.to_i32,
    )
    ctx.emit(wrapped_instance)
    copied_instance = Adamas::HIR::Copy.new(
      function.next_value_id, union_type, wrapped_instance.id,
    )
    ctx.emit(copied_instance)

    wrapped_class = Adamas::HIR::UnionWrap.new(
      function.next_value_id, union_type, class_literal.id, box_type.id.to_i32,
    )
    ctx.emit(wrapped_class)
    copied_class = Adamas::HIR::Copy.new(
      function.next_value_id, union_type, wrapped_class.id,
    )
    ctx.emit(copied_class)

    phi = Adamas::HIR::Phi.new(function.next_value_id, union_type)
    phi.add_incoming(function.entry_block, copied_instance.id)
    phi.add_incoming(function.entry_block, copied_class.id)
    phi.add_incoming(function.entry_block, copied_instance.id)
    ctx.emit(phi)

    facts = converter.__test_source_block_result_value_facts(ctx, phi.id)
    facts.size.should eq(2)
    facts.should contain({box_type, false})
    facts.should contain({box_type, true})
    converter.__test_source_argument_value_name(ctx, phi.id).should eq(
      "SourceBlockFacts::Box | SourceBlockFacts::Box.class"
    )
  end

  it "preserves grounded instance and class facts across a retagged Copy" do
    converter, ctx, function = source_block_result_value_facts_fixture
    owner = converter.module.intern_type(
      Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "SourceBlockFacts::RetaggedOwner")
    )
    instance = function.add_param("instance", owner)
    ctx.register_type(instance.id, owner)
    type_value = function.add_param("type_value", owner)
    ctx.register_type(type_value.id, owner)
    ctx.mark_type_literal(type_value.id)

    instance_copy = Adamas::HIR::Copy.new(function.next_value_id, Adamas::HIR::TypeRef::POINTER, instance.id)
    ctx.emit(instance_copy)
    type_copy = Adamas::HIR::Copy.new(function.next_value_id, Adamas::HIR::TypeRef::POINTER, type_value.id)
    ctx.emit(type_copy)
    converter.__test_source_block_result_value_facts(ctx, instance_copy.id).should eq([{owner, false}])
    converter.__test_source_block_result_value_facts(ctx, type_copy.id).should eq([{owner, true}])

    phi = Adamas::HIR::Phi.new(function.next_value_id, owner)
    phi.add_incoming(function.entry_block, instance.id)
    phi.add_incoming(function.entry_block, type_value.id)
    ctx.emit(phi)
    mixed_copy = Adamas::HIR::Copy.new(function.next_value_id, Adamas::HIR::TypeRef::POINTER, phi.id)
    ctx.emit(mixed_copy)
    converter.__test_source_block_result_value_facts(ctx, mixed_copy.id).should eq([{owner, true}, {owner, false}])
  end

  it "keeps explicit source facts as the owner of an enum extraction Copy" do
    converter, ctx, function = source_block_result_value_facts_fixture
    enum_type = converter.module.intern_type(
      Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "SourceBlockFacts::EnumValue")
    )
    source = function.add_param("source", enum_type)
    ctx.register_type(source.id, enum_type)
    extracted = Adamas::HIR::Copy.new(function.next_value_id, Adamas::HIR::TypeRef::INT32, source.id)
    ctx.emit(extracted)
    ctx.register_source_value_facts(extracted.id, [{Adamas::HIR::TypeRef::INT32, false}])

    converter.__test_source_block_result_value_facts(ctx, extracted.id).should eq([
      {Adamas::HIR::TypeRef::INT32, false},
    ])
  end

  it "treats a numeric Cast result as its target type" do
    converter, ctx, function = source_block_result_value_facts_fixture
    source = function.add_param("source", Adamas::HIR::TypeRef::UINT64)
    ctx.register_type(source.id, Adamas::HIR::TypeRef::UINT64)
    cast = Adamas::HIR::Cast.new(
      function.next_value_id,
      Adamas::HIR::TypeRef::INT32,
      source.id,
      Adamas::HIR::TypeRef::INT32,
    )
    ctx.emit(cast)

    facts = converter.__test_source_block_result_value_facts(ctx, cast.id)
    facts.should eq([{Adamas::HIR::TypeRef::INT32, false}])
  end

  it "terminates on a loop Phi and returns its grounded leaf" do
    converter, ctx, function = source_block_result_value_facts_fixture
    value_type = converter.module.intern_type(
      Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "SourceBlockFacts::Item")
    )
    value = function.add_param("value", value_type)
    ctx.register_type(value.id, value_type)

    entry_scope = function.get_block(function.entry_block).scope
    loop_block = function.create_block(entry_scope)
    loop_phi = Adamas::HIR::Phi.new(function.next_value_id, value_type)
    ctx.emit(loop_phi)
    loop_phi.add_incoming(function.entry_block, value.id)
    loop_phi.add_incoming(loop_block, loop_phi.id)

    converter.__test_source_block_result_value_facts(ctx, loop_phi.id).should eq([
      {value_type, false},
    ])
  end

  it "represents a missing value as Nil and omits NoReturn leaves" do
    converter, ctx, function = source_block_result_value_facts_fixture
    converter.__test_source_block_result_value_facts(ctx, nil).should eq([
      {Adamas::HIR::TypeRef::NIL, false},
    ])

    no_return_type = converter.module.intern_type(
      Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "NoReturn")
    )
    no_return = function.add_param("no_return", no_return_type)
    ctx.register_type(no_return.id, no_return_type)
    converter.__test_source_block_result_value_facts(ctx, no_return.id).should be_empty
  end
end
