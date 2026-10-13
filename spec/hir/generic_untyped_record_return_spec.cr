require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_generic_record_return_source(reverse : Bool) : Adamas::HIR::AstToHir
  reads = if reverse
            <<-CRYSTAL
              def read_u64 : UInt64
                make(4294967296_u64).value
              end

              def read_u32 : UInt32
                make(4294967295_u32).value
              end
            CRYSTAL
          else
            <<-CRYSTAL
              def read_u32 : UInt32
                make(4294967295_u32).value
              end

              def read_u64 : UInt64
                make(4294967296_u64).value
              end
            CRYSTAL
          end
  source = <<-CRYSTAL
    struct Info(T)
      getter value : T

      def initialize(@value : T)
      end
    end

    def make(value)
      Info.new(value: value)
    end

    #{reads}
  CRYSTAL

  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(
    parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source},
  )
  converter.arena = parsed.arena

  class_nodes = parsed.roots.compact_map do |expr_id|
    parsed.arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
  end
  def_nodes = parsed.roots.compact_map do |expr_id|
    parsed.arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
  end

  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter
end

private def calls_in(function : Adamas::HIR::Function) : Array(Adamas::HIR::Call)
  function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
end

private def fields_in(function : Adamas::HIR::Function) : Array(Adamas::HIR::FieldGet)
  function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::FieldGet))
end

describe "untyped generic factory return ownership" do
  [false, true].each do |reverse|
    it "keeps exact Info return and field types when #{reverse ? "UInt64" : "UInt32"} is lowered first" do
      converter = lower_generic_record_return_source(reverse)
      u32_factory = converter.module.function_by_name("make$UInt32")
      u64_factory = converter.module.function_by_name("make$UInt64")
      u32_reader = converter.module.function_by_name("read_u32")
      u64_reader = converter.module.function_by_name("read_u64")

      [u32_factory, u64_factory, u32_reader, u64_reader].each { |function| function.should_not be_nil }

      u32_factory_type = converter.module.get_type_descriptor(u32_factory.not_nil!.return_type)
      u64_factory_type = converter.module.get_type_descriptor(u64_factory.not_nil!.return_type)
      u32_factory_type.should_not be_nil
      u64_factory_type.should_not be_nil
      u32_factory_type.not_nil!.name.should eq("Info(UInt32)")
      u64_factory_type.not_nil!.name.should eq("Info(UInt64)")
      u32_factory.not_nil!.return_type.should_not eq(u64_factory.not_nil!.return_type)

      u32_call = calls_in(u32_reader.not_nil!).find { |call| call.method_name == "make$UInt32" }
      u64_call = calls_in(u64_reader.not_nil!).find { |call| call.method_name == "make$UInt64" }
      u32_call.should_not be_nil
      u64_call.should_not be_nil
      u32_call.not_nil!.type.should eq(u32_factory.not_nil!.return_type)
      u64_call.not_nil!.type.should eq(u64_factory.not_nil!.return_type)

      u32_field = fields_in(u32_reader.not_nil!).find { |field| field.field_name == "@value" }
      u64_field = fields_in(u64_reader.not_nil!).find { |field| field.field_name == "@value" }
      u32_field.should_not be_nil
      u64_field.should_not be_nil
      u32_field.not_nil!.type.should eq(Adamas::HIR::TypeRef::UINT32)
      u64_field.not_nil!.type.should eq(Adamas::HIR::TypeRef::UINT64)
    end
  end
end
