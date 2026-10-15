require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_method_pointer_argument_probe(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  program = parser.parse_program
  raise "parser diagnostics: #{parser.diagnostics.size}" unless parser.diagnostics.empty?

  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  converter.arena = program.arena
  converter.no_prelude = true
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  main_exprs = [] of UInt64
  program.roots.each do |root_id|
    case node = program.arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      classes << node
    else
      main_exprs << root_id.index.to_u64
    end
  end
  classes.each { |node| converter.lower_class(node) }
  converter.lower_main(main_exprs)
  converter
end

private def method_pointer_argument_sources(function : Adamas::HIR::Function, call : Adamas::HIR::Call)
  copies = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Copy))
  call.args.map { |id| copies.find { |copy| copy.id == id }.try(&.source) || id }
end

describe "method pointer argument transport" do
  it "passes a typed argument to an absolute class method pointer" do
    converter = lower_method_pointer_argument_probe(<<-CRYSTAL)
      class PointerArgumentTarget
        def self.parse(value : Int32) : Int32
          value + 1
        end
      end
      callback = ->::PointerArgumentTarget.parse(Int32)
      callback.call(6)
    CRYSTAL
    thunk = converter.module.functions.find(&.name.starts_with?("__crystal_proc_")).not_nil!
    thunk.params.map(&.type).should eq([Adamas::HIR::TypeRef::INT32])
    thunk.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    call = thunk.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .find(&.method_name.starts_with?("PointerArgumentTarget.parse")).not_nil!
    method_pointer_argument_sources(thunk, call).should eq(thunk.params.map(&.id))
  end

  it "retains distinct input types in order" do
    converter = lower_method_pointer_argument_probe(<<-CRYSTAL)
      class PointerArgumentTarget
        def self.select(left : Int32, right : Int64) : Int64
          right
        end
      end
      callback = ->PointerArgumentTarget.select(Int32, Int64)
      callback.call(3, 8_i64)
    CRYSTAL
    thunk = converter.module.functions.find(&.name.starts_with?("__crystal_proc_")).not_nil!
    thunk.params.map(&.type).should eq([Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT64])
    thunk.return_type.should eq(Adamas::HIR::TypeRef::INT64)
    call = thunk.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .find(&.method_name.starts_with?("PointerArgumentTarget.select")).not_nil!
    method_pointer_argument_sources(thunk, call).should eq(thunk.params.map(&.id))
  end

  it "keeps zero-argument callbacks lazy" do
    converter = lower_method_pointer_argument_probe(<<-CRYSTAL)
      class PointerArgumentTarget
        def self.value : Int32
          42
        end
      end
      callback = ->PointerArgumentTarget.value
      callback.call
    CRYSTAL
    thunk = converter.module.functions.find(&.name.starts_with?("__crystal_proc_")).not_nil!
    thunk.params.should be_empty
    thunk.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    main = converter.module.functions.find(&.name.ends_with?("main")).not_nil!
    main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .any?(&.method_name.starts_with?("PointerArgumentTarget.value")).should be_false
  end
end
