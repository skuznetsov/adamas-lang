require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_pointerof_source_identity(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  expressions = [] of UInt64
  program.roots.each do |root|
    if node = program.arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
      classes << node
    else
      expressions << root.index.to_u64
    end
  end
  classes.each { |node| converter.lower_class(node) }
  converter.lower_main(expressions)
  converter.module
end

describe "pointerof source identity" do
  it "retains an ivar's pointee type without loading it or changing byte addressing" do
    hir = lower_pointerof_source_identity(<<-CRYSTAL)
      class PointerIdentityBox
        def initialize(@value : Int32); end
        def address
          pointerof(@value)
        end
      end
      PointerIdentityBox.new(42).address
      CRYSTAL
    method = hir.functions.find(&.name.starts_with?("PointerIdentityBox#address")).not_nil!
    instructions = method.blocks.flat_map(&.instructions)
    address = instructions.compact_map(&.as?(Adamas::HIR::PointerAdd)).first
    descriptor = hir.get_type_descriptor(address.type).not_nil!
    descriptor.name.should eq("Pointer(Int32)")
    descriptor.type_params.should eq([Adamas::HIR::TypeRef::INT32])
    address.element_type.should eq(Adamas::HIR::TypeRef::INT8)
    instructions.compact_map(&.as?(Adamas::HIR::FieldGet)).should be_empty
    instructions.compact_map(&.as?(Adamas::HIR::AddressOf)).should be_empty
  end

  it "retains an inherited ivar's pointee type" do
    hir = lower_pointerof_source_identity(<<-CRYSTAL)
      class PointerIdentityParent
        @value : Int32 = 41
      end
      class PointerIdentityChild < PointerIdentityParent
        def address
          pointerof(@value)
        end
      end
      PointerIdentityChild.new.address
      CRYSTAL
    method = hir.functions.find(&.name.starts_with?("PointerIdentityChild#address")).not_nil!
    address = method.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::PointerAdd)).first
    hir.get_type_descriptor(address.type).not_nil!.name.should eq("Pointer(Int32)")
  end

  it "retains nested pointers and full Proc signatures for local storage" do
    hir = lower_pointerof_source_identity(<<-CRYSTAL)
      value = 43
      first = pointerof(value)
      second = pointerof(first)
      callback = ->{ 73 }
      callback_address = pointerof(callback)
      CRYSTAL
    main = hir.functions.find(&.name.ends_with?("main")).not_nil!
    addresses = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::AddressOf))
    names = addresses.map { |address| hir.get_type_descriptor(address.type).not_nil!.name }
    names.should eq(["Pointer(Int32)", "Pointer(Pointer(Int32))", "Pointer(Proc(Int32))"])
  end
end
