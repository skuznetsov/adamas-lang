require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_result_type_unresolved?(name : String) : Bool
    unresolved_generic_return_type?(type_ref_for_name(name))
  end

  def __test_result_type_unresolved?(type : TypeRef) : Bool
    unresolved_generic_return_type?(type)
  end

  def __test_register_result_union(type : TypeRef, names : Array(String), refs : Array(TypeRef)) : Nil
    register_union_descriptor(type, @module.get_type_descriptor(type).not_nil!.name, names, refs)
  end

  def __test_forget_result_union_children(type : TypeRef) : Nil
    entry = union_registration_from_sidecar(type).not_nil!
    @union_descriptor_entries << UnionDescriptorRegistration.new(entry.type_ref, entry.descriptor)
  end
end

describe "registered result type resolution" do
  it "uses structural children without requiring source declarations for their heads" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    program = parser.parse_program
    converter = Adamas::HIR::AstToHir.new(program.arena)
    converter.no_prelude = true

    {"Tuple(Int32, UInt32)?", "Tuple(Pointer(Int32), Tuple(UInt8, Bool))?",
     "Pointer(Void)?", "Proc(Int32, Void)?"}.each do |name|
      converter.__test_result_type_unresolved?(name).should be_false, name
    end
  end

  it "keeps unresolved registered children provisional" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    converter = Adamas::HIR::AstToHir.new(parser.parse_program.arena)
    converter.no_prelude = true
    hir = converter.module
    t = hir.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "T"))
    unknown = hir.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "Unknown"))
    {t, unknown, Adamas::HIR::TypeRef.new(999999_u32)}.each do |child|
      tuple = hir.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Tuple, "Tuple", [child]))
      converter.__test_result_type_unresolved?(tuple).should be_true
    end
  end

  it "does not confuse a source-declared Unknown class with a provisional child" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new("class Unknown\nend"))
    program = parser.parse_program
    converter = Adamas::HIR::AstToHir.new(program.arena)
    converter.no_prelude = true
    converter.register_class(program.arena[program.roots.first].as(Adamas::Compiler::Frontend::ClassNode))
    unknown = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "Unknown"))
    tuple = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Tuple, "Tuple", [unknown]))
    converter.__test_result_type_unresolved?(tuple).should be_false
  end

  it "treats Void according to its structural slot" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    converter = Adamas::HIR::AstToHir.new(parser.parse_program.arena)
    hir = converter.module
    void = Adamas::HIR::TypeRef::VOID
    int = Adamas::HIR::TypeRef::INT32
    tuple = hir.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Tuple, "Tuple(Int32)", [void]))
    pointer = hir.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Pointer, "Pointer(T)", [void]))
    proc_input = hir.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Proc, "Proc", [void, int]))
    proc_result = hir.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Proc, "Proc", [int, void]))
    {tuple, pointer, proc_input}.each do |type|
      converter.__test_result_type_unresolved?(type).should be_true
    end
    converter.__test_result_type_unresolved?(proc_result).should be_false
  end

  it "accepts repeated resolved children without treating them as a cycle" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    converter = Adamas::HIR::AstToHir.new(parser.parse_program.arena)
    pointer = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Pointer,
      "Pointer(Int32)", [Adamas::HIR::TypeRef::INT32]))
    tuple = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Tuple,
      "Tuple", [pointer, pointer]))
    converter.__test_result_type_unresolved?(tuple).should be_false
  end

  it "rejects missing and self-repaired union witnesses" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    converter = Adamas::HIR::AstToHir.new(parser.parse_program.arena)
    union = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Union, "Int32 | Nil"))
    converter.__test_result_type_unresolved?(union).should be_true
    converter.__test_register_result_union(union, ["Int32", "Nil"], [union, Adamas::HIR::TypeRef::NIL])
    converter.__test_result_type_unresolved?(union).should be_true
    pointer_union = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Union, "Nil | Pointer(T)"))
    converter.__test_register_result_union(pointer_union, ["Nil", "Pointer(T)"], [Adamas::HIR::TypeRef::NIL, pointer_union])
    converter.__test_result_type_unresolved?(pointer_union).should be_true
    bare_pointer_union = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Union, "Nil | Pointer"))
    converter.__test_register_result_union(bare_pointer_union, ["Nil", "Pointer"], [Adamas::HIR::TypeRef::NIL, bare_pointer_union])
    converter.__test_result_type_unresolved?(bare_pointer_union).should be_true
  end

  it "snapshots source children and requires the newest generation's witnesses" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    converter = Adamas::HIR::AstToHir.new(parser.parse_program.arena)
    union = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Union, "Nil | Pointer"))
    children = [Adamas::HIR::TypeRef::NIL, Adamas::HIR::TypeRef::POINTER]
    converter.__test_register_result_union(union, ["Nil", "Pointer"], children)
    children[1] = union
    converter.__test_result_type_unresolved?(union).should be_false
    converter.__test_forget_result_union_children(union)
    converter.__test_result_type_unresolved?(union).should be_true
  end

  it "bounds structural recursion while allowing empty aggregates" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    converter = Adamas::HIR::AstToHir.new(parser.parse_program.arena)
    hir = converter.module
    empty = hir.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Tuple, "Tuple()"))
    converter.__test_result_type_unresolved?(empty).should be_false
    child = Adamas::HIR::TypeRef::INT32
    65.times do
      child = hir.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Tuple, "Tuple", [child]))
    end
    converter.__test_result_type_unresolved?(child).should be_true
  end
end
