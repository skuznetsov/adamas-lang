require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_semantic_proc_result(source : String) : {Adamas::HIR::Module, Adamas::HIR::Function}
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  converter.lower_main(program.roots.map(&.index.to_u64))
  converter.flush_pending_functions
  function = converter.module.functions.find { |fn| fn.name == "__crystal_proc_0" }.not_nil!
  {converter.module, function}
end

describe "Proc literal semantic result before branch pruning" do
  {"true", "false", "(true)", "!false"}.each do |condition|
    it "retains both result members under #{condition}" do
      mod, function = lower_semantic_proc_result("value = -> { if #{condition}; nil; else; 1; end }")
      descriptor = mod.get_type_descriptor(function.return_type).not_nil!
      descriptor.kind.should eq(Adamas::HIR::TypeKind::Union)
      descriptor.name.should contain("Nil")
      descriptor.name.should contain("Int32")
      returns = function.blocks.compact_map { |block| block.terminator.as?(Adamas::HIR::Return) }
      returns.should_not be_empty
      returns.each do |ret|
        value = ret.value.not_nil!
        instruction = function.blocks.flat_map(&.instructions).find { |inst| inst.id == value }.not_nil!
        instruction.type.should eq(function.return_type)
      end
    end
  end

  it "keeps a monomorphic result without adding a union" do
    _, function = lower_semantic_proc_result("value = -> { if true; 1; else; 2; end }")
    function.return_type.should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "retains the source result union when a typed condition prunes a branch" do
    mod, function = lower_semantic_proc_result(<<-CRYSTAL)
      value = ->(item : Int32) { if item.is_a?(Int32); 1; else; "dead"; end }
    CRYSTAL
    descriptor = mod.get_type_descriptor(function.return_type).not_nil!
    descriptor.kind.should eq(Adamas::HIR::TypeKind::Union)
    descriptor.name.should contain("Int32")
    descriptor.name.should contain("String")
  end

  it "keeps the union ABI for both dynamic branches" do
    mod, function = lower_semantic_proc_result("value = ->(flag : Bool) { if flag; nil; else; 1; end }")
    descriptor = mod.get_type_descriptor(function.return_type).not_nil!
    descriptor.kind.should eq(Adamas::HIR::TypeKind::Union)
    descriptor.name.should contain("Nil")
    descriptor.name.should contain("Int32")
  end
end
