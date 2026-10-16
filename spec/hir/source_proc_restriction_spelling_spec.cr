require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_source_proc_restriction(actual : String, declared : String) : Bool?
    source_generic_restriction_match?(actual, declared)
  end

  def __test_source_proc_type_ref(name : String) : Adamas::HIR::TypeRef?
    proc_type_ref_for_name(name)
  end
end

describe "Source Proc restriction spelling" do
  it "admits nullable arrow syntax before TypeRef erasure" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_source_proc_restriction("Nil | Proc(Int32, Nil)", "(Int32 ->)?").should eq(true)
  end

  it "preserves result discard at an implicit Nil arrow boundary" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_source_proc_restriction("Nil | Proc(Int32, String)", "(Int32 ->)?").should eq(true)
  end

  it "preserves NoReturn at an explicit result boundary" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_source_proc_restriction("Nil | Proc(Int32, NoReturn)", "(Int32 -> String)?").should eq(true)
  end

  it "compares nested Proc restrictions without erasing generic arguments" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_source_proc_restriction("Array(Proc(Int32, Nil))", "Array((Int32 ->))").should eq(true)
  end

  it "rejects a different input type" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_source_proc_restriction("Nil | Proc(String, Nil)", "(Int32 ->)?").should eq(false)
  end

  it "rejects a different input arity" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_source_proc_restriction("Nil | Proc(Int32, Int32, Nil)", "(Int32 ->)?").should eq(false)
  end

  it "rejects an incompatible explicit result type" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_source_proc_restriction("Nil | Proc(Int32, String)", "(Int32 -> Int32)?").should eq(false)
  end

  it "keeps canonical and arrow TypeRef construction equivalent" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_source_proc_type_ref("Proc(Int32, Nil)").should eq(converter.__test_source_proc_type_ref("(Int32 ->)"))
    converter.__test_source_proc_type_ref("Proc(Int32, String)").should eq(converter.__test_source_proc_type_ref("Int32 -> String"))
    converter.__test_source_proc_type_ref("Proc(Nil)").should eq(converter.__test_source_proc_type_ref("->"))
  end
end
