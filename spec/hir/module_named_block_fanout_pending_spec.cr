require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_named_module_fanout(owner : String, labels : Array(String), raw_positional_count : Int32 = 0) : {Array(String), Bool}
    receiver_type = type_ref_for_name("PendingNamedScheduler")
    function = @module.create_function("__named_fanout_caller_#{labels.join('_')}_#{raw_positional_count}", TypeRef::VOID)
    receiver = function.add_param("scheduler", receiver_type)
    context = LoweringContext.new(function, @module, @arena)
    context.register_type(receiver.id, receiver_type)
    mark_live_type(owner)
    @lazy_rta_active = true
    @rta_called_method_parts << "spawn$String_Bool_block"
    rta_record_virtual_receivers("spawn$String_Bool_block", "PendingNamedScheduler")
    @lowering_depth += 1
    begin
      ensure_virtual_call_targets_lowered(
        context, receiver.id, "spawn", [TypeRef::STRING, TypeRef::BOOL],
        true, false, true, false, labels, raw_positional_count,
      )
    ensure
      @lowering_depth -= 1
    end
    pending = @module_virtual_fanout_pending_targets.values.flat_map(&.keys)
    admitted = pending.any? { |name| module_virtual_pending_target_matches_rta?(name, owner) }
    {pending, admitted}
  end

  def __test_process_named_fanout : Nil
    process_pending_lower_functions
  end

  def __test_named_fanout_admitted?(name : String, owner : String) : Bool
    module_virtual_pending_target_matches_rta?(name, owner)
  end

  def __test_forget_named_fanout_definition(name : String) : Nil
    @function_defs.delete(name)
  end

  def __test_change_named_fanout_source(name : String) : Nil
    arena = @function_def_arenas[name]
    set_path_for_arena(arena, "/tmp/replaced_named_fanout_source.cr")
  end
end

private def pending_named_fanout_converter
  source = <<-CRYSTAL
    module PendingNamedScheduler
      abstract def spawn(*, name : String, same_thread : Bool, &block : -> Int32) : Int32
    end

    class PendingNamedWorker
      include PendingNamedScheduler

      def spawn(*, name : String, same_thread : Bool, &block : -> Int32) : Int32
        return 99 if same_thread
        block.call
      end

      def spawn(*, title : String, same_thread : Bool, &block : -> Int32) : Int32
        77
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/module_named_block_fanout_contract.cr"},
  )
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  converter
end

describe "named module block fanout pending demand" do
  it "retains the exact labeled target until lazy RTA materializes its body" do
    converter = pending_named_fanout_converter
    pending, admitted = converter.__test_named_module_fanout("PendingNamedWorker", ["name", "same_thread"])
    target = "PendingNamedWorker#spawn$String_Bool_block_named_4_name_11_same_thread"
    pending.should contain(target)
    admitted.should be_true
    converter.__test_process_named_fanout
    converter.module.has_function_with_body?(target).should be_true
    converter.module.has_function_with_body?("PendingNamedWorker#spawn$String_Bool_block_named_11_same_thread_5_title").should be_false
  end

  it "keeps equal-typed calls with different labels in separate fanout entries" do
    converter = pending_named_fanout_converter
    converter.__test_named_module_fanout("PendingNamedWorker", ["name", "same_thread"])
    pending, admitted = converter.__test_named_module_fanout("PendingNamedWorker", ["title", "same_thread"])
    pending.should contain("PendingNamedWorker#spawn$String_Bool_block_named_4_name_11_same_thread")
    pending.should contain("PendingNamedWorker#spawn$String_Bool_block_named_11_same_thread_5_title")
    admitted.should be_true
    converter.__test_process_named_fanout
    converter.module.has_function_with_body?("PendingNamedWorker#spawn$String_Bool_block_named_4_name_11_same_thread").should be_true
    converter.module.has_function_with_body?("PendingNamedWorker#spawn$String_Bool_block_named_11_same_thread_5_title").should be_true
  end

  it "does not reuse a zero-positional cache entry for incompatible source arity" do
    converter = pending_named_fanout_converter
    converter.__test_named_module_fanout("PendingNamedWorker", ["name", "same_thread"])
    # The source now claims one positional argument plus two labels, while the
    # lowered ABI supplies only two values. It cannot authenticate the same Def.
    pending, _ = converter.__test_named_module_fanout("PendingNamedWorker", ["name", "same_thread"], 1)
    pending.should contain("PendingNamedWorker#spawn$String_Bool_block")
    converter.__test_named_fanout_admitted?("PendingNamedWorker#spawn$String_Bool_block", "PendingNamedWorker").should be_false
  end

  it "rejects pending evidence after the selected definition disappears" do
    converter = pending_named_fanout_converter
    converter.__test_named_module_fanout("PendingNamedWorker", ["name", "same_thread"])
    target = "PendingNamedWorker#spawn$String_Bool_block_named_4_name_11_same_thread"
    converter.__test_forget_named_fanout_definition(target)
    converter.__test_named_fanout_admitted?(target, "PendingNamedWorker").should be_false
  end

  it "rejects pending evidence after its source context changes" do
    converter = pending_named_fanout_converter
    converter.__test_named_module_fanout("PendingNamedWorker", ["name", "same_thread"])
    target = "PendingNamedWorker#spawn$String_Bool_block_named_4_name_11_same_thread"
    converter.__test_change_named_fanout_source(target)
    converter.__test_named_fanout_admitted?(target, "PendingNamedWorker").should be_false
  end
end
