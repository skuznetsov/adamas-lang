require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

private ARENA_UNION_INDEXER_SOURCE = <<-CRYSTAL
  class Node
  end

  struct ExprId
    getter index : Int32

    def initialize(@index : Int32)
    end
  end

  class AstArena
    def []?(id : ExprId) : Node?
      nil
    end
  end

  class VirtualArena
    def []?(id : ExprId) : Node?
      nil
    end
  end

  class PageArena
    def []?(id : ExprId) : Node?
      nil
    end
  end

  alias ArenaLike = AstArena | VirtualArena | PageArena

  def probe(arena : ArenaLike, root_id : ExprId) : Node?
    arena.[]?(root_id)
  end
CRYSTAL

private def lower_arena_union_indexer_probe : {Adamas::HIR::AstToHir, Adamas::HIR::Function}
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(ARENA_UNION_INDEXER_SOURCE)
  )
  program = parser.parse_program
  raise "parser diagnostics: #{parser.diagnostics.size}" unless parser.diagnostics.empty?

  arena = program.arena
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  alias_nodes = [] of Adamas::Compiler::Frontend::AliasNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  program.roots.each do |expr_id|
    case node = arena[expr_id]
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::AliasNode
      alias_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    end
  end

  probe = def_nodes.find { |node| String.new(node.name) == "probe" }
  raise "probe definition not found" unless probe

  converter = Adamas::HIR::AstToHir.new(arena)
  alias_nodes.each { |node| converter.register_alias(node) }
  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  function = converter.lower_def(probe)
  {converter, function}
end

describe "MIR/LLVM ArenaLike explicit indexer ABI" do
  it "keeps one ExprId argument through virtual lowering" do
    converter, hir_function = lower_arena_union_indexer_probe

    hir_calls = hir_function.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call)
    end
    hir_index_calls = hir_calls.select { |call| call.method_name.includes?("#[]?") }
    hir_index_calls.size.should eq(1)
    hir_index_calls.first.args.size.should eq(1)
    hir_index_calls.first.virtual.should be_true
    hir_calls.none? { |call| call.method_name.includes?("#call") }.should be_true

    lowering = Adamas::MIR::HIRToMIRLowering.new(converter.module)
    lowering.register_union_types(converter.union_descriptor_entries)
    lowering.register_class_types(converter.class_info)
    mir_module = lowering.lower
    mir_function = mir_module.functions.find { |function| function.name == hir_function.name }
    mir_function.should_not be_nil
    mir_function = mir_function.not_nil!

    probe_calls = mir_function.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::MIR::Call)
    end
    probe_calls.size.should eq(1)
    probe_call = probe_calls.first
    probe_call.args.size.should eq(2)
    probe_callee = mir_module.functions.find { |function| function.id == probe_call.callee }
    probe_callee.should_not be_nil
    probe_callee.not_nil!.name.should contain("#[]?")

    generator = Adamas::MIR::LLVMIRGenerator.new(mir_module)
    generator.emit_type_metadata = false
    output = generator.generate

    mir_function.params.size.should eq(2)
    union_param = mir_function.params[0].type
    expr_id_param = mir_function.params[1].type
    union_type = mir_module.type_registry.get(union_param)
    union_type.should_not be_nil
    union_type.not_nil!.kind.union?.should be_true
    union_type.not_nil!.size.should eq(Adamas::MIR::TARGET_POINTER_BYTES_U64)
    union_type.not_nil!.alignment.should eq(Adamas::MIR::TARGET_POINTER_ALIGN_U32)

    dispatch = mir_module.functions.find do |function|
      function.name.starts_with?("__vdispatch__") && function.name.includes?("#[]?")
    end
    dispatch.should_not be_nil
    dispatch = dispatch.not_nil!
    dispatch.params.size.should eq(2)
    dispatch.params[0].type.should eq(union_param)
    dispatch.params[1].type.should eq(expr_id_param)
    dispatch_calls = dispatch.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::MIR::Call)
    end
    dispatch_calls.size.should eq(3)
    dispatch_calls.each { |call| call.args.size.should eq(2) }
    expected_variant_calls = [
      "AstArena#[]?$ExprId",
      "PageArena#[]?$ExprId",
      "VirtualArena#[]?$ExprId",
    ]
    dispatch_calls.map { |call| mir_module.functions.find { |function| function.id == call.callee }.not_nil!.name }
      .sort.should eq(expected_variant_calls.sort)

    variant_functions = expected_variant_calls.map do |name|
      function = mir_module.functions.find { |candidate| candidate.name == name }
      function.should_not be_nil
      function.not_nil!
    end
    variant_functions.each do |function|
      function.params.size.should eq(2)
      function.params[1].type.should eq(expr_id_param)
      function.return_type.should eq(dispatch.return_type)
    end

    mapper = Adamas::MIR::LLVMTypeMapper.new(mir_module.type_registry)
    mapper.union_descriptor_entries = mir_module.union_descriptor_entries
    mapper.union_storage_entries = mir_module.union_storage_entries
    mir_function.params.map { |param| mapper.llvm_type(param.type) }.should eq(["ptr", "ptr"])
    dispatch.params.map { |param| mapper.llvm_type(param.type) }.should eq(["ptr", "ptr"])
    variant_functions.each do |function|
      function.params.map { |param| mapper.llvm_type(param.type) }.should eq(["ptr", "ptr"])
    end

    variant_functions.each do |function|
      signature = output.lines.find do |line|
        line.includes?("define ptr @") && line.includes?(function.name.split("#").first + "$H$IDXQ$$ExprId")
      end
      signature.should_not be_nil
      signature.not_nil!.should contain("(ptr %self, ptr %id)")
    end
    probe_signature = output.lines.find { |line| line.includes?("define ptr @") && line.includes?("probe$$") }
    probe_signature.should_not be_nil
    probe_signature.not_nil!.should contain("(ptr %arena, ptr %root_id)")
    dispatch_signature = output.lines.find { |line| line.includes?("define ptr @__vdispatch__") && line.includes?("#") == false }
    dispatch_signature.should_not be_nil
    dispatch_signature.not_nil!.should contain("(ptr %recv, ptr %arg0)")
  end
end
