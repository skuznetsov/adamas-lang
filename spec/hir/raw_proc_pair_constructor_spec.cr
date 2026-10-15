require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private record RawProcPairProbe,
  converter : Adamas::HIR::AstToHir,
  construct_name : String

private def lower_raw_proc_pair_probe(
  source : String,
  source_path : String,
  stdlib_root : String = "/fixture/stdlib",
) : RawProcPairProbe
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  program = parser.parse_program
  raise "parser diagnostics: #{parser.diagnostics.size}" unless parser.diagnostics.empty?

  arena_id = program.arena.object_id.to_u64
  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {arena_id => source},
    paths_by_arena: {arena_id => source_path},
    main_arenas: [program.arena],
    stdlib_root: stdlib_root,
  )
  converter.arena = program.arena
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions

  construct = converter.module.functions.find { |function| function.name.starts_with?("construct$") }
  raise "construct function was not lowered; functions=#{converter.module.functions.map(&.name).join(", ")}" unless construct
  RawProcPairProbe.new(converter, construct.not_nil!.name)
end

private def raw_proc_pair_fixture(
  new_signature : String,
  call_expression : String,
  construct_signature : String = "fn_ptr : Void*, env_ptr : Void*",
  main_call : String = "construct(1_u64.unsafe_as(Void*), 2_u64.unsafe_as(Void*))",
  new_return_annotation : String = "self",
  construct_return_annotation : String = " : Proc",
) : String
  <<-CRYSTAL
    struct Proc
      def self.new(#{new_signature}) : #{new_return_annotation}
        raise "ordinary Proc.new body"
      end
    end

    def construct(#{construct_signature})#{construct_return_annotation}
      #{call_expression}
    end

    #{main_call}
  CRYSTAL
end

private def raw_proc_pair_function(probe : RawProcPairProbe) : Adamas::HIR::Function
  probe.converter.module.functions.find { |function| function.name == probe.construct_name }.not_nil!
end

private def raw_proc_pair_instructions(probe : RawProcPairProbe)
  raw_proc_pair_function(probe).blocks.flat_map(&.instructions).compact
end

describe "authenticated stdlib raw Proc pair constructor" do
  it "lowers only an authenticated stdlib Void* pair to MakeProc" do
    source = raw_proc_pair_fixture(
      "fn_ptr : Void*, env_ptr : Void*",
      "Proc.new(fn_ptr, env_ptr)",
    )
    probe = lower_raw_proc_pair_probe(source, "/fixture/stdlib/proc.cr")
    instructions = raw_proc_pair_instructions(probe)

    instructions.any? { |instruction| instruction.is_a?(Adamas::HIR::MakeProc) }.should be_true
    instructions.compact_map(&.as?(Adamas::HIR::Call))
      .none? { |call| call.method_name.starts_with?("Proc.new$") }.should be_true
  end

  it "leaves an identical user-defined Proc.new on the ordinary call path" do
    source = raw_proc_pair_fixture(
      "fn_ptr : Void*, env_ptr : Void*",
      "Proc.new(fn_ptr, env_ptr)",
    )
    probe = lower_raw_proc_pair_probe(source, "/fixture/app/proc.cr")
    instructions = raw_proc_pair_instructions(probe)

    instructions.none? { |instruction| instruction.is_a?(Adamas::HIR::MakeProc) }.should be_true
    instructions.compact_map(&.as?(Adamas::HIR::Call))
      .any? { |call| call.method_name.starts_with?("Proc.new$") }.should be_true
  end

  it "does not special-case a wrong pointer annotation" do
    source = raw_proc_pair_fixture(
      "fn_ptr : Void*, env_ptr : UInt8*",
      "Proc.new(fn_ptr, env_ptr)",
      "fn_ptr : Void*, env_ptr : UInt8*",
      "construct(1_u64.unsafe_as(Void*), 2_u64.unsafe_as(UInt8*))",
    )
    probe = lower_raw_proc_pair_probe(source, "/fixture/stdlib/proc.cr")
    instructions = raw_proc_pair_instructions(probe)

    instructions.none? { |instruction| instruction.is_a?(Adamas::HIR::MakeProc) }.should be_true
    instructions.compact_map(&.as?(Adamas::HIR::Call))
      .any? { |call| call.method_name.starts_with?("Proc.new$") }.should be_true
  end

  it "does not special-case a Proc.new with a non-self return annotation" do
    source = raw_proc_pair_fixture(
      "fn_ptr : Void*, env_ptr : Void*",
      "Proc.new(fn_ptr, env_ptr)",
      construct_return_annotation: "",
      new_return_annotation: "Nil",
    )
    probe = lower_raw_proc_pair_probe(source, "/fixture/stdlib/proc.cr")
    instructions = raw_proc_pair_instructions(probe)

    instructions.none? { |instruction| instruction.is_a?(Adamas::HIR::MakeProc) }.should be_true
    instructions.compact_map(&.as?(Adamas::HIR::Call))
      .any? { |call| call.method_name.starts_with?("Proc.new$") }.should be_true
  end

  it "does not special-case a block-bearing overload" do
    source = <<-CRYSTAL
      struct Proc
        def self.new(fn_ptr : Void*, env_ptr : Void*, &callback : -> Nil) : self
          raise "ordinary block Proc.new body"
        end
      end

      def construct(fn_ptr : Void*, env_ptr : Void*) : Proc
        Proc.new(fn_ptr, env_ptr) { nil }
      end

      construct(1_u64.unsafe_as(Void*), 2_u64.unsafe_as(Void*))
    CRYSTAL
    probe = lower_raw_proc_pair_probe(source, "/fixture/stdlib/proc.cr")
    instructions = raw_proc_pair_instructions(probe)

    instructions.none? { |instruction| instruction.is_a?(Adamas::HIR::MakeProc) }.should be_true
    instructions.compact_map(&.as?(Adamas::HIR::Call))
      .any? { |call| call.method_name.starts_with?("Proc.new$") }.should be_true
  end
end
