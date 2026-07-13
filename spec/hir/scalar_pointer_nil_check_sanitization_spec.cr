require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

# Test-only access to the finalized-HIR sanitization pass.
class Adamas::HIR::AstToHir
  def __test_run_scalar_pointer_nil_check_sanitization : Nil
    sanitize_scalar_pointer_nil_checks
  end
end

private def scalar_pointer_nil_test_converter(mod : Adamas::HIR::Module) : Adamas::HIR::AstToHir
  lexer = Adamas::Compiler::Frontend::Lexer.new("1")
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  Adamas::HIR::AstToHir.new(result.arena, hir_module: mod)
end

describe "AstToHir#sanitize_scalar_pointer_nil_checks" do
  it "folds a bare scalar != a null pointer to true" do
    mod = Adamas::HIR::Module.new("scalar_pointer_nil_ne")
    converter = scalar_pointer_nil_test_converter(mod)
    func = mod.create_function("scalar_pointer_nil_ne", Adamas::HIR::TypeRef::BOOL)
    scalar = func.add_param("scalar", Adamas::HIR::TypeRef::INT32)
    entry = func.get_block(func.entry_block)
    null_ptr = entry.add(Adamas::HIR::Literal.new(func.next_value_id, Adamas::HIR::TypeRef::POINTER, 0_i64))
    comparison = entry.add(Adamas::HIR::BinaryOperation.new(
      func.next_value_id,
      Adamas::HIR::TypeRef::BOOL,
      Adamas::HIR::BinaryOp::Ne,
      scalar.id,
      null_ptr.id,
    ))
    entry.terminator = Adamas::HIR::Return.new(comparison.id)

    converter.__test_run_scalar_pointer_nil_check_sanitization

    result = entry.instructions.last
    result.should be_a(Adamas::HIR::Literal)
    literal = result.as(Adamas::HIR::Literal)
    literal.id.should eq(comparison.id)
    literal.type.should eq(Adamas::HIR::TypeRef::BOOL)
    literal.value.should eq(true)
  end

  it "folds a null pointer == a bare scalar to false" do
    mod = Adamas::HIR::Module.new("scalar_pointer_nil_eq")
    converter = scalar_pointer_nil_test_converter(mod)
    func = mod.create_function("scalar_pointer_nil_eq", Adamas::HIR::TypeRef::BOOL)
    scalar = func.add_param("scalar", Adamas::HIR::TypeRef::INT64)
    entry = func.get_block(func.entry_block)
    null_ptr = entry.add(Adamas::HIR::Literal.new(func.next_value_id, Adamas::HIR::TypeRef::POINTER, 0_i64))
    comparison = entry.add(Adamas::HIR::BinaryOperation.new(
      func.next_value_id,
      Adamas::HIR::TypeRef::BOOL,
      Adamas::HIR::BinaryOp::Eq,
      null_ptr.id,
      scalar.id,
    ))
    entry.terminator = Adamas::HIR::Return.new(comparison.id)

    converter.__test_run_scalar_pointer_nil_check_sanitization

    result = entry.instructions.last
    result.should be_a(Adamas::HIR::Literal)
    literal = result.as(Adamas::HIR::Literal)
    literal.id.should eq(comparison.id)
    literal.type.should eq(Adamas::HIR::TypeRef::BOOL)
    literal.value.should eq(false)
  end

  it "keeps a real pointer compared with null as a binary operation" do
    mod = Adamas::HIR::Module.new("real_pointer_nil")
    converter = scalar_pointer_nil_test_converter(mod)
    func = mod.create_function("real_pointer_nil", Adamas::HIR::TypeRef::BOOL)
    pointer = func.add_param("pointer", Adamas::HIR::TypeRef::POINTER)
    entry = func.get_block(func.entry_block)
    null_ptr = entry.add(Adamas::HIR::Literal.new(func.next_value_id, Adamas::HIR::TypeRef::POINTER, 0_i64))
    comparison = entry.add(Adamas::HIR::BinaryOperation.new(
      func.next_value_id,
      Adamas::HIR::TypeRef::BOOL,
      Adamas::HIR::BinaryOp::Eq,
      pointer.id,
      null_ptr.id,
    ))
    entry.terminator = Adamas::HIR::Return.new(comparison.id)

    converter.__test_run_scalar_pointer_nil_check_sanitization

    result = entry.instructions.last
    result.should be_a(Adamas::HIR::BinaryOperation)
    original = comparison.as(Adamas::HIR::BinaryOperation)
    binary = result.as(Adamas::HIR::BinaryOperation)
    binary.id.should eq(original.id)
    binary.op.should eq(original.op)
    binary.left.should eq(original.left)
    binary.right.should eq(original.right)
  end

  it "keeps a scalar compared with a nonzero pointer literal as a binary operation" do
    mod = Adamas::HIR::Module.new("scalar_nonzero_pointer")
    converter = scalar_pointer_nil_test_converter(mod)
    func = mod.create_function("scalar_nonzero_pointer", Adamas::HIR::TypeRef::BOOL)
    scalar = func.add_param("scalar", Adamas::HIR::TypeRef::INT32)
    entry = func.get_block(func.entry_block)
    nonzero_ptr = entry.add(Adamas::HIR::Literal.new(func.next_value_id, Adamas::HIR::TypeRef::POINTER, 7_i64))
    comparison = entry.add(Adamas::HIR::BinaryOperation.new(
      func.next_value_id,
      Adamas::HIR::TypeRef::BOOL,
      Adamas::HIR::BinaryOp::Ne,
      scalar.id,
      nonzero_ptr.id,
    ))
    entry.terminator = Adamas::HIR::Return.new(comparison.id)

    converter.__test_run_scalar_pointer_nil_check_sanitization

    result = entry.instructions.last
    result.should be_a(Adamas::HIR::BinaryOperation)
    original = comparison.as(Adamas::HIR::BinaryOperation)
    binary = result.as(Adamas::HIR::BinaryOperation)
    binary.id.should eq(original.id)
    binary.op.should eq(original.op)
    binary.left.should eq(original.left)
    binary.right.should eq(original.right)
  end
end
