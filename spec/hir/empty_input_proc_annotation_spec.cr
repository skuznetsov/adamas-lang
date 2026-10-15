require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_proc_annotation_in_owner(
    name : String,
    owner : String,
    signature_scan : Bool,
    bindings : Hash(String, String) = {} of String => String,
  ) : Adamas::HIR::TypeRef
    old_signature_scan = @signature_scan_mode
    begin
      @signature_scan_mode = signature_scan
      with_type_param_map(bindings) { annotation_type_ref(name, owner) }
    ensure
      @signature_scan_mode = old_signature_scan
    end
  end
end

private def empty_proc_annotation_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    module ProcContext
      class CallbackOwner
        struct Input
        end
        struct Output
        end
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena)
  converter.register_module(program.arena[program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode))
  converter
end

private def proc_annotation_params(
  converter : Adamas::HIR::AstToHir,
  name : String,
  signature_scan : Bool,
  bindings : Hash(String, String) = {} of String => String,
) : Array(Adamas::HIR::TypeRef)
  ref = converter.__test_proc_annotation_in_owner(name, "ProcContext::CallbackOwner", signature_scan, bindings)
  descriptor = converter.module.get_type_descriptor(ref).not_nil!
  descriptor.kind.should eq(Adamas::HIR::TypeKind::Proc)
  descriptor.type_params
end

describe "Proc annotation syntax in a declaration owner" do
  [false, true].each do |signature_scan|
    context = signature_scan ? "signature scan" : "body lowering"

    it "keeps an empty arrow input list in #{context}" do
      converter = empty_proc_annotation_converter
      proc_annotation_params(converter, "->", signature_scan).should eq([
        Adamas::HIR::TypeRef::NIL,
      ])
      proc_annotation_params(converter, "-> Nil", signature_scan).should eq([
        Adamas::HIR::TypeRef::NIL,
      ])
      proc_annotation_params(converter, "-> Bool", signature_scan).should eq([
        Adamas::HIR::TypeRef::BOOL,
      ])
    end

    it "resolves actual input and result names in #{context}" do
      converter = empty_proc_annotation_converter
      expected = proc_annotation_params(converter, "Proc(Input, Output)", signature_scan)
      expected.size.should eq(2)
      proc_annotation_params(converter, "Input -> Output", signature_scan).should eq(expected)
    end

    it "substitutes only actual result types for an empty arrow in #{context}" do
      converter = empty_proc_annotation_converter
      proc_annotation_params(converter, "-> T", signature_scan, {"T" => "Int32"}).should eq([
        Adamas::HIR::TypeRef::INT32,
      ])
      proc_annotation_params(converter, "-> T", signature_scan, {"T" => "String"}).should eq([
        Adamas::HIR::TypeRef::STRING,
      ])
    end
  end
end
