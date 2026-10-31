require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_callsite_input_owner_remember(
    name : String,
    types : Array(TypeRef),
    literals : Array(Bool)? = nil,
    has_block : Bool = false,
    record_exact_target : Bool = true,
  ) : Nil
    remember_callsite_arg_types(
      name, types, literals, has_block: has_block,
      record_exact_target: record_exact_target,
    )
  end

  def __test_callsite_input_owner_family(
    name : String,
    types : Array(TypeRef),
    literals : Array(Bool)? = nil,
    has_block : Bool = false,
  ) : Nil
    remember_callsite_family_arg_types(name, types, literals, has_block: has_block)
  end

  def __test_callsite_input_owner_remember_default(name : String, types : Array(TypeRef)) : Nil
    remember_callsite_arg_types(name, types)
  end

  def __test_callsite_input_owner_pending(name : String)
    if entry = @pending_arg_types[name]?
      {entry.types.dup, entry.literals.try(&.dup), entry.has_block}
    end
  end

  def __test_callsite_input_owner_consume(name : String)
    if entry = pop_pending_callsite_args(name, name)
      {entry.types.dup, entry.literals.try(&.dup), entry.has_block}
    end
  end

  def __test_callsite_input_owner_arity(name : String, arity : Int32)
    if entries = @pending_arg_types_by_arity[base_callsite_key(name)]?.try(&.[arity]?)
      entries.map { |entry| {entry.types.dup, entry.literals.try(&.dup), entry.has_block} }
    end
  end

  def __test_callsite_input_owner_signature(name : String, arity : Int32, has_block : Bool, recorded : Bool = false)
    signature = call_signature_for_call(name, arity, has_block).not_nil!
    entries = recorded ? @recorded_arg_types_by_signature[signature]? : @pending_arg_types_by_signature[signature]?
    entries.try(&.map { |entry| {entry.types.dup, entry.literals.try(&.dup), entry.has_block} })
  end
end

private def callsite_input_owner_converter : Adamas::HIR::AstToHir
  Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
end

describe "callsite exact inputs and family history" do
  it "keeps a nilary physical target unchanged when a typed sibling is discovered" do
    converter = callsite_input_owner_converter
    name = "CallsiteInputOwner#step"
    converter.__test_callsite_input_owner_remember(name, ([] of Adamas::HIR::TypeRef), ([] of Bool))
    original = converter.__test_callsite_input_owner_pending(name).not_nil!

    converter.__test_callsite_input_owner_family(name, [Adamas::HIR::TypeRef::INT32], [false])

    converter.__test_callsite_input_owner_pending(name).should eq(original)
    expected = {[Adamas::HIR::TypeRef::INT32], [false], false}
    converter.__test_callsite_input_owner_arity(name, 1).not_nil!.should contain(expected)
    converter.__test_callsite_input_owner_signature(name, 1, false).not_nil!.should contain(expected)
    converter.__test_callsite_input_owner_signature(name, 1, false, recorded: true).not_nil!.should contain(expected)
  end

  it "keeps a nilary no-block target unchanged when a nilary block sibling is discovered" do
    converter = callsite_input_owner_converter
    name = "CallsiteInputOwner#step"
    converter.__test_callsite_input_owner_remember(name, ([] of Adamas::HIR::TypeRef), ([] of Bool))
    original = converter.__test_callsite_input_owner_pending(name).not_nil!

    converter.__test_callsite_input_owner_family(name, ([] of Adamas::HIR::TypeRef), has_block: true)

    converter.__test_callsite_input_owner_pending(name).should eq(original)
    block_shape = {([] of Adamas::HIR::TypeRef), nil, true}
    converter.__test_callsite_input_owner_arity(name, 0).not_nil!.should contain(block_shape)
    converter.__test_callsite_input_owner_signature(name, 0, true).not_nil!.should contain(block_shape)
    converter.__test_callsite_input_owner_signature(name, 0, true, recorded: true).not_nil!.should contain(block_shape)
    converter.__test_callsite_input_owner_signature(name, 0, false).not_nil!.should contain(original)
  end

  it "records family history without inventing exact pending inputs" do
    converter = callsite_input_owner_converter
    name = "CallsiteInputOwner#family_only"
    converter.__test_callsite_input_owner_family(
      name, [Adamas::HIR::TypeRef::INT32], [false], has_block: true)

    converter.__test_callsite_input_owner_pending(name).should be_nil
    expected = {[Adamas::HIR::TypeRef::INT32], [false], true}
    converter.__test_callsite_input_owner_arity(name, 1).not_nil!.should eq([expected])
    converter.__test_callsite_input_owner_signature(name, 1, true).not_nil!.should eq([expected])
    converter.__test_callsite_input_owner_signature(name, 1, true, recorded: true).not_nil!.should eq([expected])
  end

  it "publishes exact inputs even when the same family shape was already recorded after consumption" do
    converter = callsite_input_owner_converter
    base = "CallsiteInputOwner#repeat"
    target = "#{base}$Int32"
    types = [Adamas::HIR::TypeRef::INT32]
    converter.__test_callsite_input_owner_remember(target, types, [false])
    consumed = converter.__test_callsite_input_owner_consume(target).not_nil!
    converter.__test_callsite_input_owner_pending(target).should be_nil

    2.times do
      converter.__test_callsite_input_owner_family(base, types, [false])
    end
    converter.__test_callsite_input_owner_pending(base).should be_nil
    converter.__test_callsite_input_owner_pending(target).should be_nil

    # Consumption removes pending buckets while recorded history and dedup
    # remain. Repeating the family shape must still permit exact publication.
    converter.__test_callsite_input_owner_remember(target, types, [false])
    converter.__test_callsite_input_owner_pending(target).should eq(consumed)
    converter.__test_callsite_input_owner_signature(base, 1, false, recorded: true).not_nil!.size.should eq(1)
  end

  it "keeps exact publication as the default for existing callers" do
    converter = callsite_input_owner_converter
    name = "CallsiteInputOwner#default$Int32"
    types = [Adamas::HIR::TypeRef::INT32]
    converter.__test_callsite_input_owner_remember_default(name, types)

    snapshot = converter.__test_callsite_input_owner_pending(name).not_nil!
    snapshot[0].should eq(types)
    snapshot[1].should be_nil
    snapshot[2].should be_false
  end
end
