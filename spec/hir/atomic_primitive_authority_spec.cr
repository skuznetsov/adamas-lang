require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def authorized_atomic_load_call(id : Adamas::HIR::ValueId = 3_u32) : Adamas::HIR::Call
  call = Adamas::HIR::Call.without_receiver(
    id,
    Adamas::HIR::TypeRef::INT32,
    "Atomic::Ops.load$Int32",
    [4_u32, 5_u32, 6_u32],
  )
  authority = Adamas::HIR::Call::AtomicPrimitiveAuthority.new(
    "load",
    "load_atomic",
    "Atomic::Ops.load",
    call.method_name,
    101_u64,
    202_u64,
    call.id,
    Adamas::HIR::Call::AtomicPrimitiveAuthority.argument_key(call.args),
    call.args.size,
    Adamas::HIR::Call::NO_RECEIVER,
    Adamas::HIR::Call::NO_BLOCK,
    false,
    call.type.id,
  )
  call.authorize_atomic_primitive!(authority)
  call
end

private def lower_atomic_authority_source(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/atomic_primitive_authority_spec.cr"},
  )
  converter.no_prelude = true

  enum_nodes = [] of Adamas::Compiler::Frontend::EnumNode
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  main_exprs = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::EnumNode
      enum_nodes << node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    else
      main_exprs << root_id.index.to_u64
    end
  end

  enum_nodes.each { |node| converter.register_enum(node) }
  module_nodes.each { |node| converter.register_module(node) }
  module_nodes.each { |node| converter.lower_module(node) }
  converter.lower_main(main_exprs) unless main_exprs.empty?
  converter.flush_pending_functions
  converter
end

describe "exact Atomic source primitive call authority" do
  it "rejects a direct mutation of the exposed argument array" do
    call = authorized_atomic_load_call
    call.atomic_primitive_authority_for_current_shape.not_nil!.operation.should eq("load")

    call.args << 7_u32

    call.atomic_primitive_authority_for_current_shape.should be_nil
  end

  it "drops authority on target, args setter, or call configuration changes" do
    rekeyed = authorized_atomic_load_call
    rekeyed.method_name = "Atomic::Ops.other$Int32"
    rekeyed.atomic_primitive_authority_for_current_shape.should be_nil

    rearged = authorized_atomic_load_call
    rearged.args = [4_u32, 5_u32]
    rearged.atomic_primitive_authority_for_current_shape.should be_nil

    reconfigured = authorized_atomic_load_call
    reconfigured.configure_with_receiver(
      9_u32,
      reconfigured.method_name,
      reconfigured.args,
      false,
    )
    reconfigured.atomic_primitive_authority_for_current_shape.should be_nil
  end

  it "preserves authority through an identical same-ID block replacement only" do
    block = Adamas::HIR::Block.new(0_u32, 0_u32)
    original = authorized_atomic_load_call
    block.add(original)
    same_call = Adamas::HIR::Call.without_receiver(
      original.id,
      original.type,
      original.method_name,
      original.args.dup,
    )
    block.replace(0, same_call)
    same_call.atomic_primitive_authority_for_current_shape.not_nil!.operation.should eq("load")

    changed_call = Adamas::HIR::Call.without_receiver(
      same_call.id,
      same_call.type,
      same_call.method_name,
      [4_u32, 5_u32, 8_u32],
    )
    block.replace(0, changed_call)
    changed_call.atomic_primitive_authority_for_current_shape.should be_nil
  end

  it "drops authority when a same-call replacement changes only the result type" do
    block = Adamas::HIR::Block.new(0_u32, 0_u32)
    original = authorized_atomic_load_call
    block.add(original)

    changed_result_call = Adamas::HIR::Call.without_receiver(
      original.id,
      Adamas::HIR::TypeRef::UINT64,
      original.method_name,
      original.args.dup,
    )
    block.replace(0, changed_result_call)

    changed_result_call.atomic_primitive_authority_for_current_shape.should be_nil
  end

  it "publishes only the exact annotated Atomic Def receipt, not its ordinary sibling" do
    converter = lower_atomic_authority_source(<<-CRYSTAL)
      module LLVM
        enum AtomicOrdering
          Relaxed = 2
        end
      end

      module Atomic
        module Ops
          @[Primitive(:load_atomic)]
          def self.load(ptr : T*, ordering : LLVM::AtomicOrdering, volatile : Bool) : T forall T
          end

          def self.load(ptr : Int32*, ordering : Int32, volatile : Bool) : Int32
            66_i32
          end
        end
      end

      wide = 65_u64
      Atomic::Ops.load(pointerof(wide), LLVM::AtomicOrdering::Relaxed, false)
      narrow = 65_i32
      Atomic::Ops.load(pointerof(narrow), 2_i32, false)
    CRYSTAL

    main = converter.module.function_by_name("__adamas_main")
    main.should_not be_nil
    calls = main.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
    atomic_calls = calls.select { |call| call.method_name.starts_with?("Atomic::Ops.load") }
    annotated_call = atomic_calls.find { |call| call.type == Adamas::HIR::TypeRef::UINT64 }
    ordinary_call = atomic_calls.find { |call| call.type == Adamas::HIR::TypeRef::INT32 }

    annotated_call.should_not be_nil
    annotated_call.not_nil!.atomic_primitive_authority_for_current_shape.not_nil!.operation.should eq("load")
    ordinary_call.should_not be_nil
    ordinary_call.not_nil!.atomic_primitive_authority_for_current_shape.should be_nil
  end
end
