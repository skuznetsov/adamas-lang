require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"

class Adamas::HIR::AstToHir
  def __test_ivar_type_name(type : TypeRef) : String
    get_type_name_from_ref(type)
  end

  def __test_ivar_type_arguments(type : TypeRef) : Array(TypeRef)
    @module.get_type_descriptor(type).try(&.type_params) || [] of TypeRef
  end

  def __test_ivar_type_kind(type : TypeRef)
    @module.get_type_descriptor(type).not_nil!.kind
  end

  def __test_registered_ivar_type(owner : String, name : String) : TypeRef
    @class_info[owner].ivars.find(&.name.==(name)).not_nil!.type
  end
end

private def generic_pointer_ivar_registration(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena)
  converter.no_prelude = true
  converter.arena = program.arena
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  converter
end

describe "generic pointer ivar inference" do
  it "registers the included module field as the generic wrapper around a pointer" do
    converter = generic_pointer_ivar_registration(<<-CRYSTAL)
      module GenericPointerIvarWrappedSource
        @value = Crystal::ThreadLocalValue(LibPCRE2::MatchData*).new
      end

      class GenericPointerIvarWrappedOwner
        include GenericPointerIvarWrappedSource
      end
    CRYSTAL

    type = converter.__test_registered_ivar_type("GenericPointerIvarWrappedOwner", "@value")
    converter.__test_ivar_type_name(type).should eq("Crystal::ThreadLocalValue(LibPCRE2::MatchData*)")
    args = converter.__test_ivar_type_arguments(type)
    args.size.should eq(1)
    converter.__test_ivar_type_name(args[0]).should eq("Pointer(LibPCRE2::MatchData)")
  end

  it "registers a true pointer field as Pointer" do
    converter = generic_pointer_ivar_registration(<<-CRYSTAL)
      module GenericPointerIvarRawSource
        @value = Pointer(UInt8).null
      end

      class GenericPointerIvarRawOwner
        include GenericPointerIvarRawSource
      end
    CRYSTAL

    type = converter.__test_registered_ivar_type("GenericPointerIvarRawOwner", "@value")
    converter.__test_ivar_type_name(type).should eq("Pointer(UInt8)")
  end

  it "preserves a qualified nilable pointee behind a pointer" do
    converter = generic_pointer_ivar_registration(<<-CRYSTAL)
      module GenericRestrictedPointerIvarSource
        @pointer_to_nilable = Crystal::ThreadLocalValue(LibPCRE2::MatchData?*).new
      end

      class GenericRestrictedPointerIvarOwner
        include GenericRestrictedPointerIvarSource
      end
    CRYSTAL

    pointer_to_nilable = converter.__test_registered_ivar_type("GenericRestrictedPointerIvarOwner", "@pointer_to_nilable")
    converter.__test_ivar_type_name(pointer_to_nilable).should eq("Crystal::ThreadLocalValue(LibPCRE2::MatchData?*)")
    pointee_args = converter.__test_ivar_type_arguments(pointer_to_nilable)
    pointee_args.size.should eq(1)
    converter.__test_ivar_type_kind(pointee_args[0]).should eq(Adamas::HIR::TypeKind::Pointer)
    union_pointee = converter.__test_ivar_type_arguments(pointee_args[0])
    union_pointee.size.should eq(1)
    converter.__test_ivar_type_kind(union_pointee[0]).should eq(Adamas::HIR::TypeKind::Union)
    converter.__test_ivar_type_name(union_pointee[0]).should contain("LibPCRE2::MatchData")
    converter.__test_ivar_type_name(union_pointee[0]).should contain("Nil")
  end
end
